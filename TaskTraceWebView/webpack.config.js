const path = require("path");
const { sources } = require("webpack");

class EmitIndexHTMLPlugin {
  apply(compiler) {
    compiler.hooks.thisCompilation.tap("EmitIndexHTMLPlugin", (compilation) => {
      compilation.hooks.processAssets.tap(
        {
          name: "EmitIndexHTMLPlugin",
          stage: compiler.webpack.Compilation.PROCESS_ASSETS_STAGE_ADDITIONAL
        },
        () => {
          const html = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>TaskTrace WebView</title>
    <style>
      :root {
        color-scheme: light dark;
        --surface: rgba(60, 60, 67, 0.08);
        --surface-strong: rgba(60, 60, 67, 0.12);
        --surface-elevated: rgba(255, 255, 255, 0.90);
        --border: rgba(60, 60, 67, 0.16);
        --grid: rgba(60, 60, 67, 0.15);
        --edge: rgba(60, 60, 67, 0.22);
        --text-primary: #111111;
        --text-secondary: rgba(60, 60, 67, 0.85);
        --accent: #4d94e0;
        --node-activity: #86c8ba;
        --node-screenshot: #f0c98b;
        --node-stroke: rgba(255, 255, 255, 0.95);
        --knowledge-file-edge: rgba(60, 60, 67, 0.24);
        --knowledge-bridge-edge: rgba(125, 142, 179, 0.30);
        --knowledge-entity-edge: rgba(111, 86, 179, 0.24);
        --knowledge-file-node: rgba(158, 204, 238, 0.66);
        --knowledge-file-node-selected: rgba(170, 214, 246, 0.88);
        --knowledge-file-node-stroke: rgba(15, 23, 42, 0.42);
        --knowledge-node: rgba(202, 185, 238, 0.66);
        --knowledge-node-stroke: rgba(15, 23, 42, 0.36);
        --knowledge-node-selected: rgba(215, 198, 246, 0.92);
        --knowledge-node-selected-stroke: rgba(15, 23, 42, 0.62);
        --shadow: 0 22px 46px rgba(15, 23, 42, 0.12);
      }

      * {
        box-sizing: border-box;
      }

      html,
      body {
        margin: 0;
        width: 100%;
        height: 100%;
        overflow: hidden;
        background: transparent;
        font-family: "SF Pro Text", "Helvetica Neue", sans-serif;
      }

      #app {
        width: 100%;
        height: 100%;
      }

      .graph-shell {
        position: relative;
        width: 100%;
        height: 100%;
        border-radius: 18px;
        overflow: hidden;
        background:
          radial-gradient(circle at 14% 8%, rgba(77, 148, 224, 0.12), transparent 28%),
          radial-gradient(circle at 82% 86%, rgba(134, 200, 186, 0.14), transparent 24%),
          linear-gradient(180deg, rgba(255,255,255,0.52), rgba(255,255,255,0.18));
      }

      .graph-svg {
        display: block;
        width: 100%;
        height: 100%;
      }

      .graph-tooltip {
        position: absolute;
        width: 420px;
        max-width: calc(100% - 36px);
        pointer-events: none;
        opacity: 0;
        transform: translateY(12px) scale(0.96);
        transform-origin: top left;
        transition:
          opacity 240ms ease,
          transform 320ms cubic-bezier(0.2, 0.8, 0.2, 1);
      }

      .graph-tooltip.is-visible {
        opacity: 1;
        transform: translateY(0) scale(1);
      }

      .graph-tooltip.is-visible.is-swapping {
        opacity: 0.6;
        transition: opacity 80ms ease;
      }

      .tooltip-card {
        padding: 14px 16px;
        border-radius: 16px;
        background: var(--surface-elevated);
        border: 1px solid var(--border);
        box-shadow: var(--shadow);
        backdrop-filter: blur(14px);
      }

      .tooltip-row + .tooltip-row {
        margin-top: 10px;
      }

      .tooltip-label {
        display: block;
        margin-bottom: 3px;
        color: var(--text-secondary);
        font-size: 11px;
        font-weight: 700;
        letter-spacing: 0.04em;
        text-transform: uppercase;
      }

      .tooltip-value {
        display: block;
        color: var(--text-primary);
        font-size: 13px;
        line-height: 1.5;
        word-break: break-word;
      }

      @media (prefers-color-scheme: dark) {
        :root {
          --surface: rgba(255, 255, 255, 0.06);
          --surface-strong: rgba(255, 255, 255, 0.1);
          --surface-elevated: rgba(34, 39, 48, 0.88);
          --border: rgba(255, 255, 255, 0.1);
          --grid: rgba(255, 255, 255, 0.08);
          --edge: rgba(255, 255, 255, 0.16);
          --text-primary: rgba(244, 247, 250, 0.96);
          --text-secondary: rgba(225, 231, 238, 0.76);
          --accent: #7fc2f0;
          --node-activity: #8bdac8;
          --node-screenshot: #f6d28f;
          --node-stroke: rgba(17, 24, 39, 0.95);
          --knowledge-file-edge: rgba(226, 232, 240, 0.24);
          --knowledge-bridge-edge: rgba(180, 198, 235, 0.30);
          --knowledge-entity-edge: rgba(197, 184, 248, 0.24);
          --knowledge-file-node: rgba(164, 208, 240, 0.68);
          --knowledge-file-node-selected: rgba(178, 218, 248, 0.90);
          --knowledge-file-node-stroke: rgba(7, 10, 18, 0.46);
          --knowledge-node: rgba(208, 190, 240, 0.68);
          --knowledge-node-stroke: rgba(7, 10, 18, 0.42);
          --knowledge-node-selected: rgba(220, 202, 248, 0.94);
          --knowledge-node-selected-stroke: rgba(7, 10, 18, 0.64);
          --shadow: 0 24px 54px rgba(0, 0, 0, 0.32);
        }

        .graph-shell {
          background:
            radial-gradient(circle at 14% 8%, rgba(127, 194, 240, 0.12), transparent 28%),
            radial-gradient(circle at 82% 86%, rgba(139, 218, 200, 0.14), transparent 24%),
            linear-gradient(180deg, rgba(255,255,255,0.02), rgba(255,255,255,0.01));
        }
      }

      svg text,
      .tooltip-card {
        user-select: none;
      }

      svg {
        touch-action: none;
      }

      .graph-shell,
      .tooltip-card,
      .tooltip-value {
        margin: 0;
      }
    </style>
  </head>
  <body>
    <main id="app"></main>
    <script src="./bundle.js"></script>
  </body>
</html>
`;
          compilation.emitAsset("index.html", new sources.RawSource(html));
        }
      );
    });
  }
}

module.exports = {
  mode: "development",
  entry: path.resolve(__dirname, "src/index.js"),
  output: {
    path: path.resolve(__dirname, "dist"),
    filename: "bundle.js",
    clean: true
  },
  plugins: [new EmitIndexHTMLPlugin()]
};
