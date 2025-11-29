# details <img src="docs/details-animated-logo.svg" align ="right" alt="" width ="150"/>

A Quarto extension for creating collapsible sections using `<details>` and `<summary>` HTML elements without writing raw HTML.

## Installation

To install the `details` Quarto extension, follow these steps:

1. Open your terminal.
2. Execute the following command:

```sh
quarto add coatless-quarto/details
```

This command will download and install the Quarto extension under the `_extensions` subdirectory of your Quarto project. If you are using version control, ensure that you include this directory in your repository.

## Usage

### Syntax with attribute

Use the `.details` class and specify the summary text with the `summary` attribute:

```markdown
::: {.details summary="Click to see more"}
This content will be collapsible.

You can include **any** Markdown content here.
:::
```

### Syntax with heading as summary

Use any heading level as the summary text. The heading will be automatically extracted:

```markdown
::: {.details}
## Click to expand

This is the collapsible content that appears after the heading.

You can use any heading level: `##`, `###`, `####`, etc.
:::
```

### Syntax with nested summary div

For multi-line or complex summaries, use a nested `.summary` div:

```markdown
::: {.details}
::: {.summary}
**Important:** Click to expand
:::

This is the collapsible content.

- Item 1
- Item 2
:::
```

### Priority order

If multiple summary methods are used, the priority is:

1. **Attribute** (`summary="text"`) - highest priority
2. **Summary div** (`::: {.summary}`)
3. **First heading** (`##`, `###`, etc.)
4. **Default** ("Click to expand")


Example where attribute takes priority:

````markdown
::: {.details summary="This will be used"}
## This heading will be treated as content

Content here.
:::
````


## Features

The `details` extension is highly configurable across interactive (HTML)
and non-interactive (PDF, Word, Typst) formats. The next subsections
describe the available features and possible configurations.

### Open by default

Add the `open="true"` attribute to make the details open by default:

```markdown
::: {.details summary="Already expanded" open="true"}
This content is visible by default.
:::
```

### Custom ID for deep linking

Add an ID to enable direct linking to the details section:

```markdown
::: {#installation-steps .details summary="Installation Steps"}
Step-by-step installation guide...
:::
```

Users can then link directly to this section with `#installation-steps`.

### Accordion Groups

Create accordion-style behavior where details elements in the same group interact with each other. Two modes are available:

#### Exclusive Mode (Default)

Only one details element can be open at a time within a group. When a user opens one section, any other open section in the same group automatically closes. This uses the native HTML `name` attribute.

```markdown
::: {.details summary="Section 1" group="faq"}
Content for section 1.
:::

::: {.details summary="Section 2" group="faq"}
Content for section 2.
:::

::: {.details summary="Section 3" group="faq"}
Content for section 3.
:::
```

#### Synchronized Mode

All details elements in a group open and close together. When a user toggles one section, all other sections in the same group follow.

```markdown
::: {.details summary="Chapter 1 Notes" group="notes" accordion-mode="synchronized"}
Notes for chapter 1.
:::

::: {.details summary="Chapter 2 Notes" group="notes" accordion-mode="synchronized"}
Notes for chapter 2.
:::

::: {.details summary="Chapter 3 Notes" group="notes" accordion-mode="synchronized"}
Notes for chapter 3.
:::
```

#### Global Accordion Mode

Set the default accordion mode for all groups in the document:

```yaml
---
extensions:
  details:
    interactive:
      accordion-mode: "synchronized"  # or "exclusive" (default)
---
```

> [!NOTE]
>
> Accordion groups only apply to interactive (HTML) formats. 
> In non-interactive formats, all sections display normally.

### Conditional Content

Show different content based on whether the output format is interactive (HTML) or non-interactive (PDF, Word, etc.).

#### Inside details blocks

```markdown
::: {.details summary="Interactive Demo"}

::: {.interactive-only}
<iframe src="https://example.com/demo" width="100%" height="400"></iframe>
Try the interactive demo above!
:::

::: {.non-interactive-only}
Visit the online documentation at https://example.com/demo to try the interactive demo.
:::

:::
```

### Expand/Collapse Controls

Add document-wide buttons to expand or collapse all details sections at once:

```yaml
---
extensions:
  details:
    interactive:
      show-controls: true
      controls-position: "top"  # "top", "bottom", or "both"
---
```

#### Control Positions

| Position | Description |
|----------|-------------|
| `"top"` | Controls appear at the beginning of the document (default) |
| `"bottom"` | Controls appear at the end of the document |
| `"both"` | Controls appear at both the beginning and end |

#### Customizing Button Text

Customize the button labels:

```yaml
---
extensions:
  details:
    interactive:
      show-controls: true
      controls-expand-text: "Show all sections"
      controls-collapse-text: "Hide all sections"
---
```

> [!NOTE]
>
> Controls only appear in interactive (HTML) formats 
> and only when the document contains at least one details block.

### Format-Specific Behavior

The extension automatically detects whether the output format is interactive (HTML-based) or non-interactive (PDF, Word, Typst, etc.) and adjusts its behavior accordingly.

#### Interactive Formats (HTML, RevealJS, etc.)

For HTML-based formats, the extension generates native `<details>` and `<summary>` elements with:

- Full Markdown formatting support in summaries
- Accordion group support via the `name` attribute
- Accessibility attributes (`aria-label`, `id`)

#### Non-Interactive Formats (PDF, Word, Typst, etc.)

For non-interactive formats, the extension uses Quarto's Callout API to display the content. You can configure how details blocks appear using the `display` option:

| Display Mode | Description |
|--------------|-------------|
| `"show"` | Shows the full content in a callout block (default) |
| `"placeholder"` | Shows a callout with placeholder text indicating interactive content was removed |
| `"remove"` | Completely removes the details block from the output |

## Global Configuration

Configure the extension in your document's YAML front matter using the `extensions.details` key:

```yaml
---
extensions:
  details:
    debug: false  # Enable verbose logging
    interactive:
      open: false                       # Default open state for HTML
      summary: "Click to expand"   # Default summary text for HTML
      accordion-mode: "exclusive"       # "exclusive" or "synchronized"
      show-controls: false              # Show expand/collapse all buttons
      controls-position: "top"          # "top", "bottom", or "both"
      controls-expand-text: "Expand all"
      controls-collapse-text: "Collapse all"
    non-interactive:
      display: "show"                   # "show", "placeholder", or "remove"
      summary: "Details"           # Default summary text for non-interactive
      placeholder-text: "Interactive content not available in this format."
      callout-type: "note"              # Callout style: note, warning, tip, caution, important
---
```

### Instance-Level Attributes

Override global settings on individual details blocks:

#### For Interactive Formats

```markdown
::: {#my-details .details summary="Custom summary" open="true" group="accordion-1"}
This block has a custom ID, is open by default, and belongs to an accordion group.
:::
```

#### Different Summary Text for Non-Interactive

Use `non-interactive-summary` to specify alternative summary text for non-interactive formats:

````markdown
::: {.details summary="Click to expand code" non-interactive-summary="Code Example"}
```python
print("Hello, World!")
```
:::
````

In HTML, the summary will be "Click to expand code". In PDF/Word, the callout title will be "Code Example".

## Attribute Reference

### Div-Level Attributes

| Attribute | Values | Description |
|-----------|--------|-------------|
| `id` | identifier | Custom ID for deep linking (auto-generated if not provided) |
| `summary` | text | Summary/title text (highest priority, plain text) |
| `open` | `"true"`, `"false"` | Initial open state (HTML only) |
| `group` | string | Accordion group name (HTML only) |
| `accordion-mode` | `"exclusive"`, `"synchronized"` | Accordion behavior mode (HTML only) |
| `display` | `"show"`, `"placeholder"`, `"remove"` | Non-interactive display mode |
| `placeholder-text` | text | Custom placeholder message |
| `callout-type` | `"note"`, `"warning"`, `"tip"`, `"caution"`, `"important"` | Callout style for non-interactive |
| `non-interactive-summary` | text | Alternative summary for non-interactive formats |

### Global Options (extensions.details)

| Option | Default | Description |
|--------|---------|-------------|
| `debug` | `false` | Enable verbose logging |

### Global Options (extensions.details.interactive)

| Option | Default | Description |
|--------|---------|-------------|
| `open` | `false` | Default open state for all details blocks |
| `summary-text` | `"Click to expand"` | Default summary text when none specified |
| `accordion-mode` | `"exclusive"` | Default accordion behavior: `"exclusive"` (one open at a time) or `"synchronized"` (all toggle together) |
| `show-controls` | `false` | Show expand/collapse all buttons |
| `controls-position` | `"top"` | Position of controls: `"top"`, `"bottom"`, or `"both"` |
| `controls-expand-text` | `"Expand all"` | Text for the expand all button |
| `controls-collapse-text` | `"Collapse all"` | Text for the collapse all button |

### Global Options (extensions.details.non-interactive)

| Option | Default | Description |
|--------|---------|-------------|
| `display` | `"show"` | Default display mode |
| `non-interactive-summary` | `"Details"` | Default summary/title text |
| `placeholder-text` | `"Interactive content not available in this format."` | Default placeholder message |
| `callout-type` | `"note"` | Default callout type |

### Conditional Content Classes

| Class | Description |
|-------|-------------|
| `.interactive-only` | Content shown only in HTML formats |
| `.non-interactive-only` | Content shown only in PDF, Word, Typst, etc. |

## Acknowledgments

This extension was developed independently from the existing
[shortcode `details` Quarto extension](https://github.com/jmgirard/details) 
by [Jeffrey Girard](https://github.com/jmgirard). Their extension focuses 
on using Quarto's shortcode syntax for details blocks, while this extension
emphasizes a more natural Markdown syntax through `Div` usage and
additional features for non-interactive formats.
