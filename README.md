# nemesis_helper

Interactive player aid for Nemesis board game

## JSON format for reference screen

A tree of JSON files is used.  See description below and examples in `examples/` folder.

### Root JSON

The main file is always called `data.json` and contains these optional fields:

- `"languages"` - [list of supported languages](#localization) according to "preferred value" entries in the [IANA Language Subtag Registry](https://www.iana.org/assignments/language-subtag-registry/language-subtag-registry).  If localization for some text is not provided in given language then `"en"` fallback will be used.
- `"images"`/`"icons"` - [lists of images and icons used](#images-and-icons).
- `"modules"` - [list of modules](#modules).  That is, of children JSONs that should also be parsed and merged with the root JSON (if the corresponding module is enabled).
- `"tabs"` - [list of tabs](#tabs) that will be shown at the bottom.
- `"tabs_names"` - list of tabs names, this should go into [localized](#localization) version of `data.json`

### Localization

Any JSON can have it's localized version; for example, English version of `data.json` is `data_en.json`.  Localized version (according to current selected language) is always preferred.

For simplicity it's recommended to put all localized text into corresponding localized JSONs, while non-localized JSON should only contain metadata.

### Modules

Try this in main `data.json`:

```json
"modules": [
    {
        "name": "base"
    }
]
```

Then in `base.json`/`base_en.json` you can have module description and English content accordingly.

Allowed fields:
- `"images"`/`"icons"` - same as in top level `data.json`.
- `"default"`-  whether module is enabled on app's first start.
- `"description"` - allow module to be selectable by user on settings screen.
- `"reference"` - list of reference chapters of JSON map type, each of them can have these fields:
    - `"id"` - optional chapter's id, useful for creating links to it.
    - `"text"` - optional chapter's text, see [formatting](#formatting-of-text) below.
    - `"nested"` - list of nested sub-chapters that can have all the same fields as this one.

    Note that the top level of `"reference"` is reserved for specifying tabs and cannot have `"text"` field.

### Tabs

```json
    "tabs": [
        {
            "icon": "icon.webp",
            "icon_material": "text-box-outline",
            "widget": {
                ...
            }
        }
    ]
```

- `"icon"` or `"icon_material"` will be drawn on tab, first refers to an [icon specified earlier](#images-and-icons) and second refers to a name from [Material spec](https://pictogrammers.com/library/mdi/).
- `"widget"` refers to one of supported [widgets](#widgets)

### Widgets

Special GUI elements that can be embedded, currently allowed only in tabs.

```json
"widget": {
    "type": ...
}
```

- `"type"` - see below for supported types
- Other fields are dependent on widget's type

#### json_id

```json
"widget": {
    "type": "json_id",
    "id": "unique_id",
    "search_bar": true,
    "root": "tab_help"
}
```

- `"id"` - same as for `"reference"`, a globally unique id.
- `"search_bar"` - whether to show a search bar on top.
- `"root"` - point at `"reference"` to show in this widget.

### Patches

Any JSON can be patched with special files containing small fixes.  To do this, create another JSON containing patches (JSON objects with 'id' and edited fields) and reference it:

`base_en.json`

```json
"patches": [
    "patch1"
]
```

`base_en_patch1.json`

```json
[
    {
        "id": "id of patched object",
        "text": "patched text field"
    }
]
```

### Formatting of "text"

To avoid boilerplate the text style is based on it's nesting level.  After the top level that is reserved for tabs, there are another 5 levels with different styles:
1. Top-level header.  Collapsible, shown in uppercase for normal text and shown as-is for table of contents.
2. Second-level header.  Collapsible.
3. Third-level header.  Much smaller then the first two.
4. Text.  This is the most used level.
5. Comments.  Use for small sized commentary to the text.

"text" can also contain an array of strings instead of a single string, each one is rendered as a separate paragraph.

#### Bold and italics

Same as Markdown: `*` for *italic* and `**` for **bold**.  Use backslash to escape `\*` and another backslash to escape JSON parsing, so `\\*` becomes just `*`.

#### Hyperlinks

Use `"id"` field to assign identificator to a chapter and Markdown syntax to create a link to it: `[link text](#chapter_id)`.

#### Images and icons

First declare used images and icons in "images" and "icons" sections correspondingly:

```json
"icons": [
    {
        "id": "icon_computer",
        "path": "computer.png"
    }
],
"images": [
    {
        "id": "image_objectives",
        "path": "objectives.webp"
    }
]
```

`"path"` stands for path to file in backend.  Then use Markdown syntax to reference them by `"id"`: `![label](#image_or_icon_id)`

Images can have additional attributes specified like this: `![label](#image_or_icon_id){ float=left width=20 }`.  Supported attributes are:
- `float`: float the image to the left or the right
- `width`: width to render the image with

Icons are rendered with the same height as text surrounding them, while images by default try to fill the screen without cropping.  Label is not rendered but is taken into account when searching text.

## TODO

### Design

- [ ] Background
- [ ] Retro animations
- [ ] Animated lines on top and left?

### Rules reference

- [ ] Fill reference data in database

### Game session

- [ ] Session tokens in database
- [ ] Add goals to database
- [ ] Add characters to database
- [ ] In game allow fetching of random goals for different modes and characters
- [ ] CEO can see other players goals

### Message chat for secret conversations

- [ ] Bottom navigation bar: Reference (done) + Game (done) + Chat (new)
- [ ] Choosing player
- [ ] Sending message
- [ ] Receiving message

### Cooperative mode