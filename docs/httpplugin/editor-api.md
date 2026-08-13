# Mankai Editor API Specification

This specification describes the endpoints your server must implement to support the in-app editor in [mankai](https://github.com/nohackjustnoobb/mankai).

> Before reading this, make sure you are already familiar with the [Mankai API Specification](api.md). All of the shared types referenced here (`Manga`, `Chapter`, `Status`, `Genre`, etc.) are defined there.

## Table of Contents

- [Manga Management](#manga-management)
  - [`POST /edit/manga`](#post-editmanga)
  - [`DELETE /edit/manga/:id`](#delete-editmangaid)
  - [`POST /edit/manga/:id/cover`](#post-editmangaidcover)
- [Chapter Group Management](#chapter-group-management)
  - [`POST /edit/chapter-group`](#post-editchapter-group)
  - [`DELETE /edit/chapter-group/:id`](#delete-editchapter-groupid)
  - [`GET /edit/chapter-group/:id/chapters`](#get-editchapter-groupidchapters)
- [Chapter Management](#chapter-management)
  - [`POST /edit/chapter`](#post-editchapter)
  - [`DELETE /edit/chapter/:id`](#delete-editchapterid)
  - [`POST /edit/chapter/order`](#post-editchapterorder)
  - [`POST /edit/chapter/:id/images`](#post-editchapteridimages)
  - [`POST /edit/images/delete`](#post-editimagesdelete)
  - [`POST /edit/images/order`](#post-editimagesorder)

## Manga Management

### `POST /edit/manga`

Insert or update a manga entry. If the request body's `id` field is omitted, the server should generate a new ID, otherwise, the existing manga with that ID is updated.

**Request Body**

```ts
interface MangaRequest {
  id?: string; // Omit for new manga — the server may generate its own ID.
  title?: string;
  status?: Status;
  description?: string;
  authors: string[];
  genres: Genre[];
  remarks?: string;
}
```

**Response — `200 OK`**

```ts
interface MangaResponse {
  id: string;
}
```

### `DELETE /edit/manga/:id`

Delete a manga and all of its associated chapter groups, chapters, and images.

**Path Parameters**

| Parameter | Type     | Description     |
| :-------- | :------- | :-------------- |
| `id`      | `string` | The manga's ID. |

### `POST /edit/manga/:id/cover`

Insert or update the cover image for a manga. The request body should be the raw image bytes, the server should infer the format from the request's `Content-Type` header (e.g. `image/png`, `image/jpeg`).

**Path Parameters**

| Parameter | Type     | Description     |
| :-------- | :------- | :-------------- |
| `id`      | `string` | The manga's ID. |

**Request Body**

Raw image data (e.g. `image/png`, `image/jpeg`).

## Chapter Group Management

A chapter group is a named container for a set of related chapters (for example, a "Season 1" group, or chapters belonging to the same scanlation team).

For editable manga, every chapter group returned by `GET /manga/:id` must include its `id`. The app uses this ID for update and delete operations. Read-only implementations may omit chapter group IDs.

### `POST /edit/chapter-group`

Insert or update a chapter group. Omit `id` to create a new group, otherwise, the existing group with that ID is updated.

**Request Body**

```ts
interface ChapterGroupRequest {
  id?: string; // Omit to create a new chapter group.
  mangaId: string;
  title: string;
}
```

### `DELETE /edit/chapter-group/:id`

Delete a chapter group and all of its chapters and images.

**Path Parameters**

| Parameter | Type     | Description             |
| :-------- | :------- | :---------------------- |
| `id`      | `string` | The chapter group's ID. |

### `GET /edit/chapter-group/:id/chapters`

Get the ordered list of chapters that belong to a chapter group.

**Path Parameters**

| Parameter | Type     | Description             |
| :-------- | :------- | :---------------------- |
| `id`      | `string` | The chapter group's ID. |

**Response — `200 OK`**

```ts
type ChaptersResponse = Chapter[];

interface Chapter {
  id: string;
  title?: string;
  locked?: boolean;
}
```

## Chapter Management

### `POST /edit/chapter`

Insert or update a chapter. Omit `id` to create a new chapter, otherwise, the existing chapter with that ID is updated.

**Request Body**

```ts
interface ChapterUpsertRequest {
  id?: string; // Omit to create a new chapter.
  title: string;
  chapterGroupId: string;
}
```

### `DELETE /edit/chapter/:id`

Delete a chapter and all of its associated images.

**Path Parameters**

| Parameter | Type     | Description       |
| :-------- | :------- | :---------------- |
| `id`      | `string` | The chapter's ID. |

### `POST /edit/chapter/order`

Set the order of chapters within a chapter group. The request body is an ordered list of chapter IDs — the first ID becomes the first chapter, the second becomes the second, and so on.

**Request Body**

```ts
type ChapterOrderRequest = string[]; // Ordered list of chapter IDs
```

### `POST /edit/chapter/:id/images`

Append images to the end of a chapter. Each entry in the `images` array should be a base64-encoded image.

**Path Parameters**

| Parameter | Type     | Description       |
| :-------- | :------- | :---------------- |
| `id`      | `string` | The chapter's ID. |

**Request Body**

```ts
interface ChapterImagesRequest {
  images: string[]; // Array of image data, each encoded in base64.
}
```

### `POST /edit/images/delete`

Delete one or more images by their full URLs. Use this when removing pages from a chapter or cleaning up orphaned images.

**Request Body**

```ts
type DeleteImagesRequest = string[]; // List of image URLs to delete.
```

### `POST /edit/images/order`

Set the order of images within a chapter. The request body is an ordered list of image URLs — the first URL becomes the first image, the second becomes the second, and so on.

**Request Body**

```ts
type ImageOrderRequest = string[]; // Ordered list of image URLs.
```
