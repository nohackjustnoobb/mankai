# Mankai API Specification

To integrate your server with [mankai](https://github.com/nohackjustnoobb/mankai), it must follow this API specification.

> If you also want your server to be compatible with the in-app editor, you must additionally follow the [Mankai Editor API Specification](editor-api.md).

## Table of Contents

- [Server Information](#server-information)
  - [`GET /`](#get-)
- [Authentication (Optional)](#authentication-optional)
  - [`POST /auth/login`](#post-authlogin)
  - [`POST /auth/refresh`](#post-authrefresh)
- [Manga](#manga)
  - [`GET /manga`](#get-manga)
  - [`POST /manga`](#post-manga)
  - [`GET /manga/:id`](#get-mangaid)
  - [`GET /manga/:id/chapter/:chapterId`](#get-mangaidchapterchapterid)
- [Search](#search)
  - [`GET /search`](#get-search)
- [Suggestion](#suggestion)
  - [`GET /suggestion`](#get-suggestion)

## Server Information

### `GET /`

Retrieve information about the server.

**Response — `200 OK`**

```ts
interface ServerInfoResponse {
  id: string;
  authenticationEnabled: boolean;
  editorEnabled?: boolean;        // default: false
  name?: string;
  version?: string;
  description?: string;
  authors?: string[];
  repository?: string;
  availableGenres?: string[];
}
```

## Authentication (Optional)

If you want to enable authentication on your server, you must implement the following two endpoints.

> [!NOTE]
> When the client calls any endpoint other than `/auth/*` and `/`, it will include the `accessToken` in the `Authorization` header.

### `POST /auth/login`

Exchange a username and password for an access token and refresh token.

**Request Body**

```ts
interface LoginRequest {
  username: string;
  password: string;
}
```

**Response — `200 OK`**

```ts
interface LoginResponse {
  message: string;
  user: {
    // User Details (Optional)
  };
  accessToken: string;
  refreshToken: string;
}
```

### `POST /auth/refresh`

Exchange a valid refresh token for a new access token.

**Request Body**

```ts
interface RefreshRequest {
  refreshToken: string;
}
```

**Response — `200 OK`**

```ts
interface RefreshResponse {
  message: string;
  accessToken: string;
}
```

## Manga

These endpoints return data about manga and their chapters. Lightweight manga entries (used in lists, search, and batch lookups) share the `Manga` shape defined below; the full details endpoint returns the richer `MangaResponse` shape.

### `GET /manga`

Retrieve a paginated list of manga, optionally filtered by genre and/or status.

**Query Parameters**

| Parameter | Type     | Default   | Required | Description                                       |
| :-------- | :------- | :-------- | :------- | :------------------------------------------------ |
| `page`    | `number` | `1`       | No       | The page number to retrieve.                      |
| `genre`   | `string` | `"all"`   | No       | Filter results by a single genre.                 |
| `status`  | `number` | `0` (Any) | No       | Filter by status: `0` = Any, `1` = OnGoing, `2` = Ended. |

**Response — `200 OK`**

```ts
type MangaListResponse = Manga[];

interface Chapter {
  id: string;
  title?: string;
  locked?: boolean;
}

interface Manga {
  id: string;
  title?: string;
  cover?: string;          // URL — absolute, or relative to the server's base URL
  status?: Status;
  latestChapter?: Chapter;
}

enum Status {
  Any = 0,
  OnGoing = 1,
  Ended = 2,
}
```

### `POST /manga`

Retrieve lightweight details for a specific list of manga. This is useful for batch lookups (for example, refreshing a user's library) where calling `GET /manga/:id` for each entry would be too slow.

**Request Body**

```ts
type MangaRequest = string[];   // Array of manga IDs
```

**Response — `200 OK`**

Returns the same `MangaListResponse` shape as [`GET /manga`](#get-manga).

### `GET /manga/:id`

Retrieve full details for a single manga, including its description, authors, genres, and the complete list of chapters grouped by chapter group.

**Path Parameters**

| Parameter | Type     | Description       |
| :-------- | :------- | :---------------- |
| `id`      | `string` | The manga's ID.   |

**Response — `200 OK`**

```ts
interface MangaResponse {
  id: string;
  title?: string;
  cover?: string;          // URL — absolute, or relative to the server's base URL
  status?: Status;
  readingDirection?: ReadingDirection;
  latestChapter?: Chapter;
  description?: string;
  updatedAt?: number;      // Unix timestamp in milliseconds
  authors: string[];
  genres: Genre[];
  chapters: Record<string, Chapter[]>;   // Keyed by chapter group ID
  remarks?: string;
  editable?: boolean;     // Whether this manga can be edited; defaults to true
}

enum Genre {
  All = "all",
  Action = "action",
  Romance = "romance",
  Yuri = "yuri",
  BoysLove = "boysLove",
  SchoolLife = "schoolLife",
  Adventure = "adventure",
  Harem = "harem",
  SpeculativeFiction = "speculativeFiction",
  War = "war",
  Suspense = "suspense",
  FanFiction = "fanFiction",
  Comedy = "comedy",
  Magic = "magic",
  Horror = "horror",
  Historical = "historical",
  Sports = "sports",
  Mature = "mature",
  Mecha = "mecha",
  Otokonoko = "otokonoko",
}

enum Status {
  Any = 0,
  OnGoing = 1,
  Ended = 2,
}

enum ReadingDirection {
  LeftToRight = 1,
  RightToLeft = 2,
  Vertical = 3,
}

interface Chapter {
  id: string;
  title?: string;
  locked?: boolean;
}
```

### `GET /manga/:id/chapter/:chapterId`

Retrieve the page images for a specific chapter. The response is a list of image URLs that may be absolute or relative to the server's base URL.

**Path Parameters**

| Parameter    | Type     | Description           |
| :----------- | :------- | :-------------------- |
| `id`         | `string` | The manga's ID.       |
| `chapterId`  | `string` | The chapter's ID.     |

**Response — `200 OK`**

```ts
// Array of image URLs (absolute, or relative to the server's base URL).
type ChapterResponse = string[];
```

## Search

### `GET /search`

Search for manga by title.

**Query Parameters**

| Parameter | Type     | Default | Required | Description                  |
| :-------- | :------- | :------ | :------- | :--------------------------- |
| `query`   | `string` | `null`  | Yes      | The search query string.     |
| `page`    | `number` | `1`     | No       | The page number to retrieve. |

**Response — `200 OK`**

Returns the same `MangaListResponse` shape as [`GET /manga`](#get-manga).

## Suggestion

### `GET /suggestion`

Get autocomplete suggestions for a search query. This is typically used to power a typeahead in the search bar.

**Query Parameters**

| Parameter | Type     | Default | Required | Description                              |
| :-------- | :------- | :------ | :------- | :--------------------------------------- |
| `query`   | `string` | `null`  | Yes      | The query string to get suggestions for. |

**Response — `200 OK`**

```ts
// Array of suggested manga titles.
type SuggestionResponse = string[];
```
