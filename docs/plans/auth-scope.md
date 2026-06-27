# Lurk.Auth — Implementation Scope

## Vision

Lurk auth must be competitive with Laravel (Breeze/Fortify), Django (contrib.auth), Rails 8 (generator), and Next.js (Better Auth). The differentiators:

1. **Compile-time enforcement:** protected routes provably require auth
2. **No DB required:** SQLite as default, pluggable to any backend
3. **Composable guards:** auth, roles, rate limiting as a unified pipeline
4. **Beginner-friendly:** looks like PHP, hides Haskell

## Dependencies

| Package | Purpose | New? |
|---------|---------|------|
|`crypton`|Password hashing|**No.** Already transitive via connection → tls → crypton-1.1.4 |
|`sqlite-simple`|SQLite user store | **Yes.** lightweight (12 deps), bundles C SQLite |

No other new dependencies. crypton is the key win — zero binary impact.

## Core Design Decisions

### User type

#### Option A: Typeclass (recommended)

```Haskell
class User user where
    userId    :: user -> Text
    userEmail :: user -> Text
    userRole  :: user -> Text
    -- extensible: developers add fields via instances
```

**Pros:** Extensible, any data type can be a User. Aligns with Laravel's Authenticatable contract.  
**Cons:** Orphan instances if user type is defined outside Lurk. Beginners must understand typeclasses.

#### Option B: Concrete record

```Haskell
data User = User
    { userId    :: Text
    , userEmail :: Text
    , userRole  :: Text
    }
```

**Pros:** Simple, no typeclass overhead. Beginners see exactly what a User is.  
**Cons:** Inflexible. Can't add fields without modifying Lurk source.

#### Option C: Record + type alias pattern

```Haskell
-- Lurk provides:
data CoreUser = CoreUser { coreUserId :: Text, coreUserEmail :: Text, coreUserRole :: Text }

-- Developer wraps it:
data MyUser = MyUser { myUser :: CoreUser, myCompany :: Text }
```

**Pros:** Extensible without typeclasses. Developer composes their own type.  
**Cons:** Boilerplate. Two layers to navigate.

**Recommendation:** Option A (typeclass). It's the most Haskell-idiomatic, aligns with Laravel's guard/provider pattern, and is extensible. The orphan instance concern is minor — most projects define their User type in their own codebase, not in Lurk.

### UserStore backend

#### Option A: Typeclass (recommended)

```Haskell
class UserStore store user | store -> user where
    findUserByEmail    :: store -> Text -> IO (Maybe user)
    validateCredentials :: store -> Text -> Text -> IO (Maybe user)
    createUser         :: store -> Text -> Text -> Text -> IO (Maybe user)  -- email, password, role
    -- more methods as needed
```

**Pros:** Open for extension (new backends without modifying Lurk). Compile-time backend selection.  
**Cons:** Typeclass overhead, potential orphan instances.

#### Option B: Record of functions

```Haskell
data UserStore user = UserStore
    { findUserByEmail    :: Text -> IO (Maybe user)
    , validateCredentials :: Text -> Text -> IO (Maybe user)
    , createUser         :: Text -> Text -> Text -> IO (Maybe user)
    }
```

**Pros:** Easier to test (inject mock store). No orphan instances. Simpler for beginners.  
**Cons:** Not open for extension without modifying the record type. No compile-time dispatch.

**Recommendation:** Option A (typeclass). The sqlite-simple SQLiteStore instance is the reference implementation. Developers who want a different backend implement the typeclass.

### Compile-time enforcement

**The problem:** `get path action` `expects action :: Action ()`. Can't change this without rewriting the routing system.

#### Option A: Proof-carrying requireAuth (recommended for v1)

```Haskell
data Auth = Auth deriving (Eq, Show)

requireAuth :: UserStore store user => store -> FallbackAction -> Action (user, Auth)
```

The Auth value is a proof that auth was checked. Functions that require authentication can demand Auth in their signature:

```Haskell
-- This function can only be called after requireAuth
deleteUser :: UserStore store user => store -> Auth -> Text -> Action ()
deleteUser store proof userId = do
    -- proof proves caller has authenticated
    -- ...

-- This function CANNOT call deleteUser without Auth
publicAction = do
    deleteUser store ??? "user-123"  -- compile error: no Auth value
```

**Pros:** Documented intent, enables future compile-time checks, type-level documentation.  
**Cons:** Not enforced at the route level (developer can ignore Auth). Partial solution.

#### Option B: Typed routes (future, after v1)

```Haskell
-- Routes carry auth requirement in their type
data Route (auth :: AuthLevel) = Route Text

type PublicRoute = Route 'Public
type ProtectedRoute = Route 'Protected

get :: ProtectedRoute -> (Auth -> Action ()) -> LurkApp  -- requires Auth proof
getPublic :: PublicRoute -> Action () -> LurkApp          -- no Auth needed
```

**Pros:** Full compile-time enforcement. Can't call a protected route without proof.  
**Cons:** Major routing system rewrite. Breaks existing API. Complex for beginners.

#### Option C: Phantom types on Action (future, after v1)

```Haskell
newtype AuthAction a = AuthAction (Action a)

requireAuth :: UserStore store user => store -> FallbackAction -> AuthAction (user, Auth)
```

**Pros:** Type-level distinction between auth'd and non-auth'd actions.  
**Cons:** Requires changing action types throughout the framework. Major refactor.

**Recommendation:** Option A for v1. Options B or C as future enhancements when the routing system is more mature. The proof-carrying approach is practical, useful today, and a stepping stone to full enforcement.

### login function

#### Option A: All-in-one (recommended)

```Haskell
login :: UserStore store user => store -> Text -> Text -> Action (Maybe user)
login store email password = do
    mUser <- validateCredentials store email password
    case mUser of
        Nothing  -> pure Nothing
        Just user -> do
            store <- getStoreFromVault
            sid <- ...
            setSessionValue store sid "user_id" (userId user)
            pure (Just user)
```

Beginner calls one function. It validates, creates session, sets cookie.

#### Option B: Separated (for advanced users)

```Haskell
-- Low-level: just validate
validateLogin :: UserStore store user => store -> Text -> Text -> IO (Maybe user)

-- Low-level: just create session
createAuthSession :: UserStore store user => SessionStore -> user -> Action ()

-- High-level: all-in-one
login :: UserStore store user => store -> Text -> Text -> Action (Maybe user)
login store email password = do
    mUser <- liftIO $ validateLogin store email password
    case mUser of
        Nothing  -> pure Nothing
        Just user -> createAuthSession store user >> pure (Just user)
```

**Pros:** Advanced users can customize the flow (e.g., add logging, custom session data).  
**Cons:** More API surface.

**Recommendation:** Option B. login does everything. validateLogin and createAuthSession are exported for advanced use. Beginners use login, experts compose from lower-level functions.

### Auth guards (composable pipeline)

Extends the existing FormGuard pattern:

```Haskell
-- New type, analogous to FormGuard:
type AuthGuard user = user -> Action (Either user user)

-- Built-in guards:
requireRole :: UserStore store user => store -> Text -> AuthGuard user
requireRole store role user
    | hasRole user role = pure (Right user)
    | otherwise = pure (Left user)

-- Composable pipeline:
authPipeline :: UserStore store user => store -> Text -> AuthGuard user
authPipeline store role = requireRole store role

-- Usage in controller:
dashboardAction = do
    (user, proof) <- requireAuth store do
        flashError "Please log in"
        redirect "/login/"
    case authPipeline store "admin" user of
        Right admin -> render $ dashboardView admin
        Left _      -> do
            flashError "Access denied"
            redirect "/404/"
```

**Note:** The AuthGuard type is a future extensibility point. For v1, `requireAuth` and `requireRole` are standalone functions, not a pipeline. The pipeline is v2 work.

### `requireAuth` behavior

Like form guards, fallback action on failure:

```Haskell
requireAuth :: UserStore store user => store -> Action () -> Action (user, Auth)
requireAuth store onFail = do
    mUser <- getCurrentUser store
    case mUser of
        Just user -> pure (user, Auth)
        Nothing   -> onFail >> fallback
  where
    fallback = pure (error "requireAuth: fallback must not return (e.g. redirect)")
```

The error "unreachable" is safe because `onFail` should always redirect or finish. This is the same pattern as form guards.

#### Alternative (safer but more complex):

```Haskell
data AuthResult user = Authenticated user | Failed

requireAuth :: UserStore store user => store -> Action () -> Action (AuthResult user)
```

**Recommendation:** Use `AuthResult` for safety. The error "unreachable" pattern is fragile. `AuthResult` is explicit:

```Haskell
dashboardAction = do
    result <- requireAuth store do
        flashError "Please log in"
        redirect "/login/"
    case result of
        Authenticated user -> render $ dashboardView user
        Failed             -> pure ()  -- unreachable: redirect already happened
```

## SQLite Store

### Schema

```SQL
CREATE TABLE IF NOT EXISTS lurk_users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'user',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

### Thread safety

`sqlite-simple` connections are NOT thread-safe. Options:

1. **MVar Connection** (recommended)**:** serialize all access through an MVar. Simple, correct, low overhead for a users table (low contention).
2. **WAL mode:** allows concurrent reads, serializes writes. Better performance but still needs MVar for writes.
3. **Connection pool:** overkill for a users table.

**Recommendation:** `MVar` Connection. Simple, correct, sufficient for the target scale.

### Migration

No built-in migration support in `sqlite-simple`. Options:

1. **Startup check** (recommended)**:** run CREATE TABLE IF NOT EXISTS at startup. For a single users table, this is sufficient.
2. **Version tracking:** add a schema_version table, run ALTER TABLE as needed. More complex but handles schema evolution.
3. **External migration tool:** delegate to a library or CLI. Adds complexity.

**Recommendation:** Startup check for v1. Version tracking when Lurk.DB arrives.

### Default store initialization

```Haskell
-- In Main.hs:
newSQLiteStore "auth.db" >>= \store -> runLurk cfg (router store)

-- In Lurk:
newSQLiteStore :: FilePath -> IO SQLiteStore
newSQLiteStore path = do
    conn <- open path
    execute_ conn "PRAGMA journal_mode=WAL"
    execute_ conn createUsersTable
    store <- SQLiteStore <$> newMVar conn
    pure store
```

Zero-config. Developer calls `newSQLiteStore "auth.db"` and gets a working user store.

## Security

| Concern | Mitigation |
| --- | --- |
| Password hashing | crypton bcrypt, cost 12 (configurable) |
| Timing attacks | validatePassword from crypton uses constant-time comparison |
| Session fixation | Session ID regenerated on login (existing Lurk behavior) |
| CSRF | Automatic on POST routes (existing Lurk behavior) |
| Brute force | Login throttling: max N attempts per M minutes per IP |
| User enumeration | Generic error messages ("Invalid email or password") |
| Cookie security | HttpOnly, Secure (production), SameSite=Lax (existing Lurk) |
| Remember me | Separate long-lived token, stored in DB, revocable |
| SQLite encryption | Not built-in. Developer uses SQLCipher if needed (external) |


## Scope boundaries

### In v1

- Lurk.Auth module
- User typeclass (userId, userEmail, userRole)
- UserStore typeclass (findUserByEmail, validateCredentials, createUser)
- SQLiteStore (default, file-based, MVar-protected)
- login / logout / currentUser / requireAuth / requireRole
- rememberMe (long-lived cookie)
- Login throttling (session-based)
- Password hashing via crypton bcrypt
- Flash message integration in auth failures

### NOT in v1 (future)

- OAuth / Social login (requires http-client)
- 2FA / TOTP
- Email verification
- Passkeys / WebAuthn
- Multi-device session management
- Password reset flow
- Typed routes (full compile-time enforcement)
- Lurk.Admin (auto-generated from User type)
- Rate limiting per-route (separate feature)
- API token auth (Sanctum-equivalent)

## Files

File	Change
Lurk/Auth.hs	New — User typeclass, UserStore typeclass, login/logout/currentUser/requireAuth/requireRole
Lurk/Auth/SQLite.hs	New — SQLiteStore implementation
Lurk/Session.hs	Minor — add getCurrentUserId helper (reads user_id from session)
Lurk/Prelude.hs	Export auth functions
lurk.cabal	Add sqlite-simple, crypton to build-depends; add Lurk.Auth, Lurk.Auth.SQLite to exposed-modules
test/AuthSpec.hs	New — tests for login, logout, guards, throttling

## Migration path

When Lurk.DB arrives:

1. UserStore typeclass gains additional methods (listUsers, updateUser, deleteUser)
2. DBStore implementation added (Postgres, MySQL via Lurk.DB)
3. SQLiteStore remains as default for simple projects
4. Auth code unchanged — same login/requireAuth API
5. Password reset, email verification added as new functions

## Questions to revisit after Lurk.DB

- Should UserStore support pagination? (for admin panels)
- Should roles be a typeclass too? (for type-safe role checks)
- Should Lurk.Admin auto-generate from User type? (like Django admin)
- Should we add rememberMe token to the DB (for revocation)?