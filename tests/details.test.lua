-- details tests. Run from the repo root: quarto pandoc lua path/to/qtest.lua
local t = require("qtest")

-- Regression: the div's own classes and attributes were dropped instead of
-- carried over to <details>.
t.test("html: a .details div becomes <details> with its id, classes and attributes, and the summary attribute", function()
  local r = t.render("basic.qmd", "html")
  r:succeeded()
  t.count(r.text, "<details ", 4)
  t.contains(r.text, '<details id="my-details" class="details extra" aria-label="Attribute summary" data-x="1">\n<summary>Attribute summary</summary>')
end)

-- Regressions: rich summaries were flattened to strings, so their math was
-- lost; and any heading in the block became the summary, not only a leading one.
t.test("html: a .summary div or a leading heading is the summary, with its math; otherwise summary-text", function()
  local r = t.render("basic.qmd", "html")
  t.contains(r.text, '<summary>Div summary with <span class="math inline">\\(x^2\\)</span></summary>')
  t.contains(r.text, '<summary>Heading summary with <span class="math inline">\\(y_1\\)</span></summary>')
  t.in_order(r.text, { "<summary>Show me</summary>", "Intro paragraph.", "Not a summary</h2>", "Body four." })
end)

t.test("open: the document default opens blocks, and open=\"false\" keeps one closed", function()
  local r = t.render("open.qmd", "html")
  r:succeeded()
  t.contains(r.text, '<details id="default-open" class="details" open="" aria-label="Opens by default">')
  t.contains(r.text, '<details id="closed" class="details" aria-label="Stays closed">')
end)

t.test("group: exclusive groups share a name; synchronized groups get data attributes and one script", function()
  local r = t.render("groups.qmd", "html")
  r:succeeded()
  t.count(r.text, 'name="faq"', 2)
  t.count(r.text, 'data-details-group="steps" data-accordion-mode="synchronized"', 2)
  t.count(r.text, "querySelectorAll('details[data-accordion-mode=\"synchronized\"]')", 1)
end)

-- Regression: expand all and collapse all also opened and closed other
-- <details> on the page, such as Quarto's code-fold blocks.
t.test("show-controls: buttons with the custom texts at top and bottom, acting only on details blocks", function()
  local r = t.render("controls.qmd", "html")
  r:succeeded()
  t.in_order(r.text, {
    'id="details-controls-top"', ">Open everything</button>", ">Close everything</button>",
    "First paragraph.", "Last paragraph.", 'id="details-controls-bottom"',
  })
  t.count(r.text, "document.querySelectorAll('details.details')", 2)
end)

-- Regression: the top controls went before the first heading, where RevealJS
-- made them an untitled slide of their own.
t.test("revealjs: the top controls go under the first slide's heading", function()
  local r = t.render("slides.qmd", "revealjs")
  r:succeeded()
  t.in_order(r.text, { '<section id="first-slide" class="slide level2">', "<h2>First slide</h2>", 'id="details-controls-top"', '<details id="details-1"' })
  t.count(r.text, '<section class="slide level2">', 0)
end)

t.test("interactive-only content stays in HTML and non-interactive-only content in Typst", function()
  local html = t.render("conditional.qmd", "html")
  html:succeeded()
  t.contains(html.text, "<p>Web only.</p>")
  t.not_contains(html.text, "Print only.")
  local typ = t.render("conditional.qmd", "typst")
  typ:succeeded()
  t.contains(typ.text, "Print only.")
  t.not_contains(typ.text, "Web only.")
end)

-- Regressions: callout titles from rich summaries lost their math, and custom
-- IDs were dropped, so links to the block broke.
t.test("typst: a callout titled by the summary, with its math, the callout-type, and the custom ID", function()
  local r = t.render("basic.qmd", "typst")
  r:succeeded()
  t.in_order(r.text, { "Body one.", "Attribute summary", "fa-exclamation-triangle()", "] <my-details>" })
  t.in_order(r.text, { "Body two.", "Div summary with $x^2$", "fa-lightbulb()" })
  t.in_order(r.text, { "Body four.", "More", "fa-lightbulb()" })
end)

t.test("display: placeholder shows placeholder-text, a block's display=\"remove\" drops it, display=\"show\" keeps it", function()
  local r = t.render("display.qmd", "typst")
  r:succeeded()
  t.in_order(r.text, { "See the web version.", "Placeholder block", "Shown body.", "Shown block" })
  t.not_contains(r.text, "Hidden body.")
  t.not_contains(r.text, "Removed")
end)

t.test("pdf and docx: callouts titled by the summary, with math; pdf keeps the custom ID", function()
  local tex = t.render("basic.qmd", "latex")
  tex:succeeded()
  t.in_order(tex.text, { "\\label{my-details}", "title=\\textcolor{quarto-callout-warning-color}", "{Attribute summary}" })
  t.contains(tex.text, "{Div summary with \\(x^2\\)}")
  local docx = t.render("basic.qmd", "docx")
  docx:succeeded()
  t.in_order(docx.text, { 'Str "Attribute"', 'Math InlineMath "x^{2}"', 'Math InlineMath "y_{1}"', 'Str "More"' })
end)
