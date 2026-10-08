## Module `Catalog`

Catalog keeps a small collection of named entries.

## Constant `Catalog::DEFAULT_LIMIT`

The default number of entries returned by a search.

## Class `Catalog::Entry`

A named entry in a catalog.
This description continues on a plain comment line
until the next annotation or declaration.

## `Catalog::Entry.read_name(path)`

### Parameters

- `path` — Path to the name file.

### Returns

The stored name.

## `Catalog::Entry#initialize(name)`

### Parameters

- `name` — Name to store.

### Returns

The new entry.

## Attribute reader `Catalog::Entry#name`

The stored entry name.

## `Catalog::Entry#label()`

### Returns

The entry name.

## Alias `Catalog::Entry#title`

Alias of `Catalog::Entry#label`.

### Returns

The entry name.
