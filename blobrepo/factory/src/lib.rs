// Copyright (c) 2019-present, Facebook, Inc.
// All Rights Reserved.
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use std::{sync::Arc, time::Duration};

use cloned::cloned;
use failure_ext::prelude::*;
use failure_ext::{Error, Result};
use futures::{future::IntoFuture, Future};
use futures_ext::{try_boxfuture, BoxFuture, FutureExt};
use std::collections::HashMap;

use blobstore_factory::{make_blobstore, SqlFactory, SqliteFactory, XdbFactory};

use blobrepo::BlobRepo;
use blobrepo_errors::*;
use blobstore::Blobstore;
use bonsai_hg_mapping::{CachingBonsaiHgMapping, SqlBonsaiHgMapping};
use bookmarks::{Bookmarks, CachedBookmarks};
use cacheblob::{
    dummy::DummyLease, new_cachelib_blobstore_no_lease, new_memcache_blobstore, MemcacheOps,
};
use censoredblob::SqlCensoredContentStore;
use changeset_fetcher::{ChangesetFetcher, SimpleChangesetFetcher};
use changesets::{CachingChangesets, SqlChangesets};
use dbbookmarks::SqlBookmarks;
use filenodes::CachingFilenodes;
use memblob::EagerMemblob;
use metaconfig_types::{self, BlobConfig, Censoring, MetadataDBConfig, StorageConfig};
use mononoke_types::RepositoryId;
use repo_blobstore::RepoBlobstoreArgs;
use scuba_ext::{ScubaSampleBuilder, ScubaSampleBuilderExt};
use sql_ext::myrouter_ready;
use sqlfilenodes::{SqlConstructors, SqlFilenodes};
use std::iter::FromIterator;

#[derive(Copy, Clone, PartialEq)]
pub enum Caching {
    Enabled,
    Disabled,
}

/// Construct a new BlobRepo with the given storage configuration. If the metadata DB is
/// remote (ie, MySQL), then it configures a full set of caches. Otherwise with local storage
/// it's assumed to be a test configuration.
///
/// The blobstore config is actually orthogonal to this, but it wouldn't make much sense to
/// configure a local blobstore with a remote db, or vice versa. There's no error checking
/// at this level (aside from disallowing a multiplexed blobstore with a local db).
pub fn open_blobrepo(
    storage_config: StorageConfig,
    repoid: RepositoryId,
    myrouter_port: Option<u16>,
    caching: Caching,
    bookmarks_cache_ttl: Option<Duration>,
    censoring: Censoring,
    scuba_censored_table: Option<String>,
) -> BoxFuture<BlobRepo, Error> {
    myrouter_ready(storage_config.dbconfig.get_db_address(), myrouter_port)
        .and_then(move |()| match storage_config.dbconfig {
            MetadataDBConfig::LocalDB { path } => do_open_blobrepo(
                SqliteFactory::new(path),
                storage_config.blobstore,
                caching,
                repoid,
                myrouter_port,
                bookmarks_cache_ttl,
                censoring,
                scuba_censored_table,
            )
            .left_future(),
            MetadataDBConfig::Mysql {
                db_address,
                sharded_filenodes,
            } => do_open_blobrepo(
                XdbFactory::new(db_address, myrouter_port, sharded_filenodes),
                storage_config.blobstore,
                caching,
                repoid,
                myrouter_port,
                bookmarks_cache_ttl,
                censoring,
                scuba_censored_table,
            )
            .right_future(),
        })
        .boxify()
}

fn do_open_blobrepo<T: SqlFactory>(
    sql_factory: T,
    blobconfig: BlobConfig,
    caching: Caching,
    repoid: RepositoryId,
    myrouter_port: Option<u16>,
    bookmarks_cache_ttl: Option<Duration>,
    censoring: Censoring,
    scuba_censored_table: Option<String>,
) -> impl Future<Item = BlobRepo, Error = Error> {
    let uncensored_blobstore = make_blobstore(repoid, &blobconfig, &sql_factory, myrouter_port);

    let censored_blobs = match censoring {
        Censoring::Enabled => sql_factory
            .open::<SqlCensoredContentStore>()
            .and_then(move |censored_store| {
                let censored_blobs = censored_store
                    .get_all_censored_blobs()
                    .map_err(Error::from)
                    .map(HashMap::from_iter);
                Some(censored_blobs)
            })
            .left_future(),
        Censoring::Disabled => Ok(None).into_future().right_future(),
    };

    uncensored_blobstore.join(censored_blobs).and_then(
        move |(uncensored_blobstore, censored_blobs)| match caching {
            Caching::Disabled => new_development(
                &sql_factory,
                uncensored_blobstore,
                censored_blobs,
                scuba_censored_table,
                repoid,
            ),
            Caching::Enabled => new_production(
                &sql_factory,
                uncensored_blobstore,
                censored_blobs,
                scuba_censored_table,
                repoid,
                bookmarks_cache_ttl,
            ),
        },
    )
}

/// Used by tests
pub fn new_memblob_empty(blobstore: Option<Arc<dyn Blobstore>>) -> Result<BlobRepo> {
    let repo_blobstore_args = RepoBlobstoreArgs::new(
        blobstore.unwrap_or_else(|| Arc::new(EagerMemblob::new())),
        None,
        RepositoryId::new(0),
        ScubaSampleBuilder::with_discard(),
    );

    Ok(BlobRepo::new(
        Arc::new(SqlBookmarks::with_sqlite_in_memory()?),
        repo_blobstore_args,
        Arc::new(
            SqlFilenodes::with_sqlite_in_memory()
                .chain_err(ErrorKind::StateOpen(StateOpenError::Filenodes))?,
        ),
        Arc::new(
            SqlChangesets::with_sqlite_in_memory()
                .chain_err(ErrorKind::StateOpen(StateOpenError::Changesets))?,
        ),
        Arc::new(
            SqlBonsaiHgMapping::with_sqlite_in_memory()
                .chain_err(ErrorKind::StateOpen(StateOpenError::BonsaiHgMapping))?,
        ),
        Arc::new(DummyLease {}),
    ))
}

/// Create a new BlobRepo with purely local state. (Well, it could be a remote blobstore, but
/// that would be weird to use with a local metadata db.)
fn new_development<T: SqlFactory>(
    sql_factory: &T,
    blobstore: Arc<dyn Blobstore>,
    censored_blobs: Option<HashMap<String, String>>,
    scuba_censored_table: Option<String>,
    repoid: RepositoryId,
) -> BoxFuture<BlobRepo, Error> {
    let bookmarks = sql_factory
        .open::<SqlBookmarks>()
        .chain_err(ErrorKind::StateOpen(StateOpenError::Bookmarks))
        .from_err();

    let filenodes = sql_factory
        .open::<SqlFilenodes>()
        .chain_err(ErrorKind::StateOpen(StateOpenError::Filenodes))
        .from_err();

    let changesets = sql_factory
        .open::<SqlChangesets>()
        .chain_err(ErrorKind::StateOpen(StateOpenError::Changesets))
        .from_err();

    let bonsai_hg_mapping = sql_factory
        .open::<SqlBonsaiHgMapping>()
        .chain_err(ErrorKind::StateOpen(StateOpenError::BonsaiHgMapping))
        .from_err();

    bookmarks
        .join4(filenodes, changesets, bonsai_hg_mapping)
        .map({
            move |(bookmarks, filenodes, changesets, bonsai_hg_mapping)| {
                let scuba_builder = ScubaSampleBuilder::with_opt_table(scuba_censored_table);

                BlobRepo::new(
                    bookmarks,
                    RepoBlobstoreArgs::new(blobstore, censored_blobs, repoid, scuba_builder),
                    filenodes,
                    changesets,
                    bonsai_hg_mapping,
                    Arc::new(DummyLease {}),
                )
            }
        })
        .boxify()
}

/// If the DB is remote then set up for a full production configuration.
/// In theory this could be with a local blobstore, but that would just be weird.
fn new_production<T: SqlFactory>(
    sql_factory: &T,
    blobstore: Arc<dyn Blobstore>,
    censored_blobs: Option<HashMap<String, String>>,
    scuba_censored_table: Option<String>,
    repoid: RepositoryId,
    bookmarks_cache_ttl: Option<Duration>,
) -> BoxFuture<BlobRepo, Error> {
    fn get_cache_pool(name: &str) -> Result<cachelib::LruCachePool> {
        let err = Error::from(ErrorKind::MissingCachePool(name.to_string()));
        cachelib::get_pool(name).ok_or(err)
    }

    fn get_volatile_pool(name: &str) -> Result<cachelib::VolatileLruCachePool> {
        let err = Error::from(ErrorKind::MissingCachePool(name.to_string()));
        cachelib::get_volatile_pool(name)?.ok_or(err)
    }

    let blobstore = try_boxfuture!(new_memcache_blobstore(blobstore, "multiplexed", ""));
    let blob_pool = try_boxfuture!(get_cache_pool("blobstore-blobs"));
    let presence_pool = try_boxfuture!(get_cache_pool("blobstore-presence"));

    let blobstore = Arc::new(new_cachelib_blobstore_no_lease(
        blobstore,
        Arc::new(blob_pool),
        Arc::new(presence_pool),
    ));

    let filenodes_pool = try_boxfuture!(get_volatile_pool("filenodes"));
    let changesets_cache_pool = try_boxfuture!(get_volatile_pool("changesets"));
    let bonsai_hg_mapping_cache_pool = try_boxfuture!(get_volatile_pool("bonsai_hg_mapping"));

    let hg_generation_lease = try_boxfuture!(MemcacheOps::new("bonsai-hg-generation", ""));

    let filenodes_tier_and_filenodes = sql_factory.open_filenodes();
    let bookmarks = sql_factory.open::<SqlBookmarks>();
    let changesets = sql_factory.open::<SqlChangesets>();
    let bonsai_hg_mapping = sql_factory.open::<SqlBonsaiHgMapping>();

    filenodes_tier_and_filenodes
        .join4(bookmarks, changesets, bonsai_hg_mapping)
        .map(
            move |((filenodes_tier, filenodes), bookmarks, changesets, bonsai_hg_mapping)| {
                let filenodes = CachingFilenodes::new(
                    filenodes,
                    filenodes_pool,
                    "sqlfilenodes",
                    &filenodes_tier,
                );

                let bookmarks: Arc<dyn Bookmarks> = {
                    if let Some(ttl) = bookmarks_cache_ttl {
                        Arc::new(CachedBookmarks::new(bookmarks, ttl))
                    } else {
                        bookmarks
                    }
                };

                let changesets =
                    Arc::new(CachingChangesets::new(changesets, changesets_cache_pool));

                let bonsai_hg_mapping =
                    CachingBonsaiHgMapping::new(bonsai_hg_mapping, bonsai_hg_mapping_cache_pool);

                let changeset_fetcher_factory = {
                    cloned!(changesets, repoid);
                    move || {
                        let res: Arc<dyn ChangesetFetcher + Send + Sync> = Arc::new(
                            SimpleChangesetFetcher::new(changesets.clone(), repoid.clone()),
                        );
                        res
                    }
                };

                let scuba_builder = ScubaSampleBuilder::with_opt_table(scuba_censored_table);

                BlobRepo::new_with_changeset_fetcher_factory(
                    bookmarks,
                    RepoBlobstoreArgs::new(blobstore, censored_blobs, repoid, scuba_builder),
                    Arc::new(filenodes),
                    changesets,
                    Arc::new(bonsai_hg_mapping),
                    Arc::new(changeset_fetcher_factory),
                    Arc::new(hg_generation_lease),
                )
            },
        )
        .boxify()
}
