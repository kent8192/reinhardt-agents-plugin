# Keyed Query Cache Reference (0.4.x)

Use the Pages query cache for asynchronous reads shared by multiple components.
It gives a read a stable `QueryKey`, deduplicates concurrent requests, keeps
the last successful value visible during a background fetch, and supports
stale-time, manual refetch, and polling policies.

## When to Use `use_query`

Use `use_query` when the same server read is consumed by several components or
when a mutation must invalidate a known read. Keep `use_resource` for a
component-local read whose lifetime and dependencies are owned by one page.
Existing `use_resource` and `use_action` code remains valid.

```rust
let projects = use_query(list_projects::key(ProjectFilter { archived: false }));

match projects.phase() {
    QueryPhase::Pending => div { "Loading..." },
    QueryPhase::Success(items) => div { { render_projects(items) } },
    QueryPhase::Error(error) => div { { error.to_string() } },
}
```

For a non-server-function fetcher, construct the key with both an ID and a
fetcher: `QueryKey::new("projects", || async { list_projects().await })`.

The exact key must contain every input that changes the result. Prefer typed
key constructors or a server-function marker key over hand-built strings.
The query handle has the same Suspense tracking contract as `Resource`, so
`SuspenseBoundary::track` can coordinate the initial read.

`QueryHandle` distinguishes the initial load from a refresh:

- `is_pending()` is true before the first successful result;
- `is_fetching()` is true during a background refresh; and
- the previous successful data remains renderable while that refresh runs.

## Server-Function Keys

For a `#[server_fn]`, the generated marker module exposes `key(...)` tied to the
endpoint identity and canonical JSON arguments:

```rust
#[server_fn]
pub async fn list_projects(filter: ProjectFilter) -> Result<Vec<Project>, Error> {
    // ...
}

let key = list_projects::key(ProjectFilter { archived: false });
let projects = use_query(key);
```

Equivalent JSON objects map to the same query identity. Raw arguments are not
embedded in hydration IDs, so do not concatenate serialized arguments into a
custom hydration key.

Server functions that use request extractors or `#[inject]` parameters skip
native SSR prefetch because their request context is not available there. They
remain usable in the browser and in test mocks; show a stable pending fallback
for the client fetch.

## Mutation Invalidation

Invalidate a successful query from a mutation instead of manually copying
server response data into every consumer:

```rust
let save = use_mutation(save_project)
    .invalidates(list_projects::key(current_filter));

save.dispatch(input);
```

Only successful mutations trigger the registered refetch. Keep the key
construction in a shared module when the read has several consumers so the
mutation and query cannot drift apart.

## Review Checklist

- The key includes all result-affecting arguments and uses the server-function
  marker helper when one exists.
- Cross-component reads use `use_query`; page-local reads use `use_resource`.
- Initial pending and background fetching states are rendered separately.
- Mutations invalidate the exact successful-read key and do not refetch on
  failure.
- Request-bound or injected server functions do not assume native SSR prefetch.
- Query tests assert deduplication, stale/refetch behavior, prior-data
  visibility, invalidation, and stable hydration identity.
