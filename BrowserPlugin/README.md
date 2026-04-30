# Browser Plugin

This directory contains the Chrome native messaging setup for TaskTrace.

Current behavior:

- clicking the extension action converts the current page or file into markdown
- on X/Twitter, each tweet gets a TaskTrace action beside the Grok/Summarize button
- clicking the tweet action converts only that tweet or long-form article into markdown
- HTML pages are converted from captured DOM markup
- PDF files are converted with `pdfjs-dist`
- Word `.docx` files are converted with `mammoth`
- legacy `.doc` files are rejected with a conversion hint
- the extension sends markdown to the TaskTrace native host
- TaskTrace replies with `"Hello World!"`

Files:

- `TaskTraceChromeExtension/`
  Unpacked Chrome extension. `background.js` is the bundled output consumed by Chrome.
- `NativeMessaging/tasktrace-browser-plugin-host.sh`
  Wrapper that proxies Chrome native messaging traffic into the local TaskTrace browser socket.
- `NativeMessaging/com.tasktrace.browser_plugin.template.json`
  Native host manifest template. Replace the placeholders before installing it into Chrome's native messaging manifest location.
- `src/`
  Source for the markdown conversion, extension background worker, and X/Twitter content script.
- `test/`
  Parser tests for HTML, PDF, Word, and X/Twitter fixtures.

Notes:

- Run `npm test` to validate the parsers.
- Run `npm run build` after source changes to rebuild `TaskTraceChromeExtension/background.js`.
- The extension uses `chrome.scripting.executeScript`, so it works on DOM-backed pages where Chrome allows injection.
- For `file://` pages, Chrome requires "Allow access to file URLs" for the extension.
- The repo includes a `.docx` fixture for the Mammoth path. The older `.doc` sample remains useful as a source fixture, but the extension only parses `.docx`.
- The native host manifest must contain the real Chrome extension ID in `allowed_origins`.
- The running TaskTrace app owns the browser socket at `/tmp/tasktrace-browser-plugin.sock`. If the app is not running, the extension reports that the browser service is unavailable instead of launching TaskTrace itself.
