# Local assets

The public page makes no third-party asset requests.

## IBM Plex fonts

Source: [IBM/plex](https://github.com/IBM/plex), revision
`71f558992315a12ca1f06a2215d57962a1992162`, consulted 23 October 2026.
Only the required Latin1 WOFF2 files are included. Font bytes are unchanged:

| Local file under `public/assets/` | Fixed upstream URL |
| --- | --- |
| `IBMPlexSans-Regular-Latin1.woff2` | https://raw.githubusercontent.com/IBM/plex/71f558992315a12ca1f06a2215d57962a1992162/packages/plex-sans/fonts/split/woff2/IBMPlexSans-Regular-Latin1.woff2 |
| `IBMPlexSans-SemiBold-Latin1.woff2` | https://raw.githubusercontent.com/IBM/plex/71f558992315a12ca1f06a2215d57962a1992162/packages/plex-sans/fonts/split/woff2/IBMPlexSans-SemiBold-Latin1.woff2 |
| `IBMPlexMono-Regular-Latin1.woff2` | https://raw.githubusercontent.com/IBM/plex/71f558992315a12ca1f06a2215d57962a1992162/packages/plex-mono/fonts/split/woff2/IBMPlexMono-Regular-Latin1.woff2 |
| `OFL.txt` | https://raw.githubusercontent.com/IBM/plex/71f558992315a12ca1f06a2215d57962a1992162/LICENSE.txt |

Sans regular and semibold serve prose/headings; Mono regular serves code.
All three are preloaded. `font-display: optional` prevents a late font swap.
The fallback remains readable if fonts cannot load. IBM Plex is licensed under
SIL Open Font License 1.1; the upstream license text is retained as `OFL.txt`,
with LF line endings and trailing whitespace normalized.

## Repository logo and generated images

`public/assets/logo.svg` derives from this repository's `assets/logo.svg`.
The source path geometry is unchanged; the dark fill is changed to the approved
petrol `#142E32`. `favicon.svg` uses the same vector with a tighter viewBox.
The root `assets/` files are unchanged. Repository artwork is covered by the
repository MIT license.

`tools/generate-images.mjs` is the code-native layout source for the 1200 × 630
`social.png` and the 32 × 32 `favicon-32.png`. It renders local font/vector data
with the development Playwright Chromium tool; it fetches no remote assets.
Regenerate from `site/` with `node tools/generate-images.mjs` after installing
the recorded tools and Chromium. Social metadata declares the image dimensions.

## Historical package example

Lodash `4.17.21` follows the repository's documented example. It is labeled
historical, not current latest. On 23 October 2026 the live
https://registry.npmjs.org/lodash version list did not contain `4.99.99`.
That version is labeled illustrative wherever shown. The lookup evidence is
in ignored `reports/task-1/registry-lodash.json`.
