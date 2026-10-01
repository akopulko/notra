import Foundation
import WebKit

@MainActor
enum MarkdownMermaidRuntime {
    static func configure(_ configuration: WKWebViewConfiguration) {
        configuration.setURLSchemeHandler(MermaidResourceHandler.shared, forURLScheme: "notra-mermaid")
        configuration.userContentController.addUserScript(
            WKUserScript(source: bootstrapScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
    }

    private static let bootstrapScript = """
    (() => {
      const sections = Array.from(document.querySelectorAll('.notra-mermaid'));
      if (!sections.length) { window.notraMermaidReady = Promise.resolve(); return; }
      window.notraMermaidReady = (async () => {
        await document.fonts.ready;
        const fail = section => {
          section.dataset.notraMermaidState = 'error';
          section.querySelector('.notra-mermaid-output').replaceChildren();
          section.querySelector('.notra-mermaid-error').hidden = false;
          section.querySelector('.notra-mermaid-source').hidden = false;
        };
        if (!window.mermaid) { sections.forEach(fail); return; }
        const pdf = document.documentElement.dataset.notraRenderMode === 'pdf';
        const dark = !pdf && matchMedia('(prefers-color-scheme: dark)').matches;
        const config = {
          startOnLoad: false, securityLevel: 'strict', htmlLabels: false,
          suppressErrorRendering: true,
          fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif',
          theme: pdf ? 'neutral' : (dark ? 'dark' : 'default'), themeCSS: '',
          flowchart: { htmlLabels: false },
          dompurifyConfig: {
            FORBID_TAGS: ['script', 'iframe', 'foreignObject', 'image']
          },
          secure: [
            'secure', 'securityLevel', 'startOnLoad', 'maxTextSize', 'maxEdges',
            'htmlLabels', 'dompurifyConfig', 'themeCSS', 'fontFamily', 'theme',
            'themeVariables', 'flowchart'
          ]
        };
        const renderAll = async () => {
          window.mermaid.initialize(config);
          for (const section of sections) {
            const source = section.querySelector('.notra-mermaid-source code').textContent;
            const output = section.querySelector('.notra-mermaid-output');
            const staging = document.createElement('div');
            staging.style.cssText = 'position:absolute;visibility:hidden;left:-100000px;top:0;width:100%;';
            document.body.append(staging);
            try {
              const result = await window.mermaid.render('notra-mermaid-' + (++window.__notraMermaidID), source, staging);
              const template = document.createElement('template');
              template.innerHTML = result.svg;
              const svg = template.content.querySelector('svg');
              if (!svg) throw new Error('Missing SVG');
              svg.setAttribute('role', 'img');
              if (!svg.querySelector(':scope > title') && !svg.querySelector(':scope > desc')) {
                svg.setAttribute('aria-label', section.getAttribute('aria-label'));
              }
              const box = svg.getAttribute('viewBox')?.trim().split(/[ ,]+/).map(Number);
              if (box?.length === 4 && box.every(Number.isFinite) && box[2] > 0 && box[3] > 0) {
                svg.style.maxWidth = '100%';
                svg.style.width = box[2] + 'px'; svg.style.height = box[3] + 'px';
              }
              if (pdf) {
                const content = document.querySelector('.pdf-content');
                const bounds = content.getBoundingClientRect();
                if (!box || box.length !== 4 || !box.every(Number.isFinite) ||
                    box[2] <= 0 || box[3] <= 0) {
                  throw new Error('Invalid SVG size');
                }
                const scale = Math.min(1, bounds.width / box[2], bounds.height / box[3]);
                if (!(scale > 0) || !Number.isFinite(scale)) throw new Error('Invalid printable size');
                svg.style.width = (box[2] * scale) + 'px'; svg.style.height = (box[3] * scale) + 'px';
                section.style.cssText = 'break-inside:avoid-column;margin:0;padding:0;';
              }
              output.replaceChildren(svg);
              section.querySelector('.notra-mermaid-error').hidden = true;
              section.querySelector('.notra-mermaid-source').hidden = true;
              section.dataset.notraMermaidState = 'rendered';
            } catch (_) { fail(section); }
            finally { staging.remove(); }
          }
        };
        window.__notraMermaidID = 0;
        window.mermaid.initialize(config);
        await renderAll();
        if (!pdf) {
          matchMedia('(prefers-color-scheme: dark)').addEventListener('change', async event => {
            config.theme = event.matches ? 'dark' : 'default';
            window.notraMermaidReady = window.notraMermaidReady.then(renderAll);
            await window.notraMermaidReady;
          });
        }
      })().catch(() => {
        sections.forEach(section => {
          section.dataset.notraMermaidState = 'error';
          section.querySelector('.notra-mermaid-error').hidden = false;
          section.querySelector('.notra-mermaid-source').hidden = false;
        });
      });
    })();
    """
}

@MainActor
private final class MermaidResourceHandler: NSObject, WKURLSchemeHandler {
    static let shared = MermaidResourceHandler()
    private lazy var data = Bundle.main
        .url(forResource: "mermaid.min", withExtension: "js")
        .flatMap { try? Data(contentsOf: $0) }

    func webView(_: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.absoluteString == "notra-mermaid://bundle/mermaid.min.js",
              let data
        else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = URLResponse(
            url: url,
            mimeType: "text/javascript",
            expectedContentLength: data.count,
            textEncodingName: "utf-8"
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_: WKWebView, stop _: any WKURLSchemeTask) {}
}
