-- ============================================================================
-- Types
-- ============================================================================

---@alias DetailsAccordionMode "exclusive"|"synchronized"
---@alias DetailsControlsPosition "top"|"bottom"|"both"
---@alias DetailsDisplayMode "show"|"placeholder"|"remove"
---@alias DetailsCalloutType "note"|"warning"|"tip"|"caution"|"important"

--- Options for interactive (HTML-based) formats, from `extensions.details.interactive`.
---@class DetailsInteractiveOptions
---@field open boolean Whether details are open by default (default: false)
---@field summary_text string Default summary text when none specified (default: "Click to expand")
---@field accordion_mode DetailsAccordionMode Accordion behavior mode (default: "exclusive")
---@field show_controls boolean Whether to show expand/collapse all buttons (default: false)
---@field controls_position DetailsControlsPosition Position of controls (default: "top")
---@field controls_expand_text string Text for expand all button (default: "Expand all")
---@field controls_collapse_text string Text for collapse all button (default: "Collapse all")

--- Options for non-interactive formats (PDF, Word, Typst), from `extensions.details.non-interactive`.
---@class DetailsNonInteractiveOptions
---@field display DetailsDisplayMode Display mode (default: "show")
---@field placeholder_text string Text shown when display is "placeholder"
---@field summary_text string Default summary/title text for callouts (default: "Details")
---@field callout_type DetailsCalloutType|string Quarto callout type (default: "note"); not validated

--- Summary of a details element, in the forms the output formats need.
---@class DetailsSummary
---@field inlines? pandoc.Inlines Rich summary content from a heading or summary div; nil for plain-text summaries
---@field plain string Plain-text summary, used for `aria-label` and in place of missing inlines
---@field source "attribute"|"div"|"heading"|"default" Where the summary came from

--- One option in an option spec. The default's type decides whether the
--- metadata value is read as a boolean or a string.
---@class DetailsOptionSpec
---@field key string Metadata key (kebab-case)
---@field field string Field name in the options table
---@field default boolean|string Value used when the key is missing
---@field allowed? string[] Allowed values; others fall back to the default with a warning

-- ============================================================================
-- Default Options
-- ============================================================================

local ACCORDION_MODES = { "exclusive", "synchronized" }
local CONTROLS_POSITIONS = { "top", "bottom", "both" }
local DISPLAY_MODES = { "show", "placeholder", "remove" }

--- Options read from each section of `extensions.details`, with their defaults.
---@type table<string, DetailsOptionSpec[]>
local OPTION_SPECS = {
  ["interactive"] = {
    { key = "open", field = "open", default = false },
    { key = "summary-text", field = "summary_text", default = "Click to expand" },
    { key = "accordion-mode", field = "accordion_mode", default = "exclusive", allowed = ACCORDION_MODES },
    { key = "show-controls", field = "show_controls", default = false },
    { key = "controls-position", field = "controls_position", default = "top", allowed = CONTROLS_POSITIONS },
    { key = "controls-expand-text", field = "controls_expand_text", default = "Expand all" },
    { key = "controls-collapse-text", field = "controls_collapse_text", default = "Collapse all" }
  },
  ["non-interactive"] = {
    { key = "display", field = "display", default = "show", allowed = DISPLAY_MODES },
    { key = "placeholder-text", field = "placeholder_text", default = "Interactive content not available in this format." },
    { key = "summary-text", field = "summary_text", default = "Details" },
    { key = "callout-type", field = "callout_type", default = "note" }
  }
}

--- Div attributes that configure this extension, so they aren't copied to the HTML output.
local OPTION_ATTRIBUTES = {
  ["summary"] = true,
  ["open"] = true,
  ["group"] = true,
  ["accordion-mode"] = true,
  ["display"] = true,
  ["placeholder-text"] = true,
  ["callout-type"] = true,
  ["non-interactive-summary"] = true
}

-- ============================================================================
-- Utility Functions
-- ============================================================================

--- Converts a Pandoc MetaValue to a Lua boolean.
--- Handles boolean values directly, or stringifies and checks for "true" or empty string.
---@param val any The MetaValue to convert (not nil)
---@return boolean
local function to_boolean(val)
  if type(val) == "boolean" then
    return val
  end
  local str = pandoc.utils.stringify(val)
  return str == "true" or str == ""
end

--- Validates that a value is one of the allowed options.
--- If the value is not in the allowed list, logs a warning and returns the default.
---@param value string The value to validate
---@param allowed string[] Allowed values
---@param name string Name of the option (used in warning messages)
---@param default string Value to return if validation fails
---@return string
local function validate_option(value, allowed, name, default)
  for _, v in ipairs(allowed) do
    if value == v then
      return value
    end
  end
  quarto.log.warning(string.format("details: invalid %s '%s'. Using '%s'.", name, value, default))
  return default
end

--- Escapes special HTML characters in a string.
--- Replaces &, <, >, ", and ' with their HTML entity equivalents.
---@param str string The string to escape
---@return string escaped The escaped string safe for HTML output
local function escape_html(str)
  local replacements = {
    ["&"] = "&amp;",
    ["<"] = "&lt;",
    [">"] = "&gt;",
    ['"'] = "&quot;",
    ["'"] = "&#39;"
  }
  return (str:gsub("[&<>\"']", replacements))
end

-- ============================================================================
-- Options Parsing
-- ============================================================================

--- Reads one section of options from document metadata.
--- Missing values take the spec's default, booleans and strings are converted
--- according to the default's type, and restricted options are validated.
---@param section any The metadata section, such as `extensions.details.interactive` (may be nil)
---@param spec DetailsOptionSpec[] The options this section can hold
---@return table opts Options keyed by field name
local function read_options(section, spec)
  if type(section) ~= "table" then
    section = {}
  end
  local opts = {}
  for _, option in ipairs(spec) do
    local value = section[option.key]
    if value == nil then
      opts[option.field] = option.default
    elseif type(option.default) == "boolean" then
      opts[option.field] = to_boolean(value)
    elseif option.allowed then
      local default = option.default --[[@as string]]
      opts[option.field] = validate_option(pandoc.utils.stringify(value), option.allowed, option.key, default)
    else
      opts[option.field] = pandoc.utils.stringify(value)
    end
  end
  return opts
end

-- ============================================================================
-- Runtime State
-- ============================================================================

--- Runtime options for interactive formats (populated from document metadata).
---@type DetailsInteractiveOptions
local interactive_opts = read_options(nil, OPTION_SPECS["interactive"])

--- Runtime options for non-interactive formats (populated from document metadata).
---@type DetailsNonInteractiveOptions
local non_interactive_opts = read_options(nil, OPTION_SPECS["non-interactive"])

--- Whether the output format is interactive (HTML-based), set once from the format.
local is_interactive = false

--- Current debug mode state.
local debug_mode = false

--- Counter for auto-generating unique element IDs.
local details_counter = 0

--- Flag indicating if any synchronized accordion groups exist in the document.
--- Used to determine whether to inject synchronization JavaScript.
local has_synchronized_groups = false

--- Flag indicating if any details elements were processed.
--- Used to determine whether to inject expand/collapse controls.
local has_details_elements = false

-- ============================================================================
-- Debug Logging
-- ============================================================================

--- Logs a debug message if debug mode is enabled.
--- Messages are prefixed with "[details]" and passed to quarto.log.info,
--- so they only appear with `quarto render --verbose`.
---@param message string The format string for the message
---@param ... any Additional arguments passed to string.format
local function debug_log(message, ...)
  if not debug_mode then
    return
  end
  local formatted = string.format("[details] " .. message, ...)
  quarto.log.info(formatted)
end

-- ============================================================================
-- Configuration
-- ============================================================================

--- Meta filter: initializes all runtime options from document metadata.
--- Parses the `extensions.details` metadata section and caches whether the
--- output format is interactive. Debug mode is parsed first to enable logging
--- during initialization.
---@param meta pandoc.Meta The full document metadata
local function initialize_options(meta)
  -- "html:js" covers every HTML-based format that runs JavaScript
  is_interactive = quarto.doc.is_format("html:js")

  local extensions = meta.extensions
  local details_meta = type(extensions) == "table" and extensions.details or nil
  if type(details_meta) ~= "table" then
    details_meta = nil
  end

  -- Parse debug option first so we can log during initialization
  if details_meta and details_meta["debug"] ~= nil then
    debug_mode = to_boolean(details_meta["debug"])
  end

  debug_log("Initializing options")
  debug_log("Output format interactive: %s", tostring(is_interactive))

  if details_meta == nil then
    debug_log("No metadata found, using defaults")
    return
  end

  interactive_opts = read_options(details_meta["interactive"], OPTION_SPECS["interactive"])
  non_interactive_opts = read_options(details_meta["non-interactive"], OPTION_SPECS["non-interactive"])

  debug_log("Interactive options: open=%s, summary_text='%s'",
    tostring(interactive_opts.open), interactive_opts.summary_text)
  debug_log("Non-interactive options: display=%s, callout_type=%s",
    non_interactive_opts.display, non_interactive_opts.callout_type)
end

--- Reads a per-element option from a div attribute, falling back to the global setting.
---@param el pandoc.Div The details Div element
---@param key string Attribute name, such as "display"
---@param fallback string The global setting
---@param allowed? string[] Allowed values; others fall back to the global setting with a warning
---@return string
local function element_option(el, key, fallback, allowed)
  local value = el.attributes[key]
  if value == nil then
    return fallback
  end
  if allowed then
    return validate_option(value, allowed, key, fallback)
  end
  return value
end

-- ============================================================================
-- Conditional Content Filtering
-- ============================================================================

--- Returns the conditional-content class of a div, if it has one.
---@param el pandoc.Div The Div element to check
---@return "interactive-only"|"non-interactive-only"|nil
local function visibility(el)
  if el.classes:includes("interactive-only") then
    return "interactive-only"
  elseif el.classes:includes("non-interactive-only") then
    return "non-interactive-only"
  end
  return nil
end

--- Processes conditional content divs, inside or outside details blocks.
--- Divs are processed bottom-up, so this runs before any enclosing details div.
--- The wrapper div is removed and only inner content is kept when it matches the format.
---@param el pandoc.Div The Div element to process
---@return pandoc.List|table|nil content The inner content blocks, an empty table (for removal), or nil (not conditional)
local function process_conditional_div(el)
  local class = visibility(el)
  if class == nil then
    return nil
  end
  if (class == "interactive-only") == is_interactive then
    debug_log("Including %s content", class)
    return el.content
  end
  debug_log("Removing %s content", class)
  return {}
end

-- ============================================================================
-- Summary Extraction
-- ============================================================================

--- Wraps plain summary text as escaped raw HTML inlines.
---@param text string The plain summary text
---@return pandoc.Inlines
local function text_to_summary_inlines(text)
  return pandoc.Inlines({ pandoc.RawInline('html', escape_html(text)) })
end

--- Removes the first block in content that satisfies a predicate and returns it.
---@param content pandoc.List Blocks to search (modified in place)
---@param pred fun(block: pandoc.Block, index: integer): boolean
---@return pandoc.Block|nil block The removed block, or nil if none matched
local function take_first(content, pred)
  for i, block in ipairs(content) do
    if pred(block, i) then
      return content:remove(i)
    end
  end
  return nil
end

--- Checks if a block is a summary div.
---@param block pandoc.Block|pandoc.Div
---@return boolean
local function is_summary_div(block)
  return block.t == "Div" and block.classes:includes('summary')
end

--- Checks if a block is a heading in first position.
--- Only a heading that is the first block counts, so headings later in the
--- content stay where they are.
---@param block pandoc.Block|pandoc.Header
---@param index integer Position of the block in the content
---@return boolean
local function is_leading_heading(block, index)
  return index == 1 and block.t == "Header"
end

--- Extracts summary information from a details div element.
--- Returns both inline and plain text versions for different output formats.
--- Rich summaries stay in the AST so that Quarto processes math and cross-references.
--- Priority order: 1) summary attribute, 2) summary div, 3) leading heading, 4) default.
---@param el pandoc.Div The details Div element
---@param default_text string Default summary text if no summary found
---@return DetailsSummary summary
---@return pandoc.List content Content blocks with summary elements removed
local function extract_summary(el, default_text)
  local content = pandoc.List(el.content)

  -- A summary div is removed even when the summary attribute takes priority
  local summary_div = take_first(content, is_summary_div)

  -- Priority 1: summary attribute
  local attr_summary = el.attributes.summary
  if attr_summary then
    debug_log("Summary from attribute: '%s'", attr_summary)
    return { plain = attr_summary, source = "attribute" }, content
  end

  -- Priority 2: summary div (supports rich formatting)
  if summary_div then
    ---@cast summary_div pandoc.Div
    debug_log("Extracted summary from div")
    return {
      -- <summary> takes phrasing content, so paragraphs become line breaks
      inlines = pandoc.utils.blocks_to_inlines(summary_div.content, pandoc.Inlines({ pandoc.LineBreak() })),
      plain = pandoc.utils.stringify(summary_div.content),
      source = "div"
    }, content
  end

  -- Priority 3: leading heading (supports rich formatting)
  local heading = take_first(content, is_leading_heading)
  if heading then
    ---@cast heading pandoc.Header
    debug_log("Extracted summary from heading (level %d)", heading.level)
    return {
      inlines = heading.content,
      plain = pandoc.utils.stringify(heading.content),
      source = "heading"
    }, content
  end

  debug_log("Using default summary")
  return { plain = default_text, source = "default" }, content
end

-- ============================================================================
-- Accessibility and ID Generation
-- ============================================================================

--- Gets or generates an ID for a details element.
--- Returns the element's existing identifier if set, otherwise generates a
--- unique "details-N" ID from an auto-incrementing counter.
---@param el pandoc.Div The details Div element
---@return string id The element's ID (existing or generated)
local function get_element_id(el)
  if el.identifier ~= "" then
    debug_log("Using provided ID: '%s'", el.identifier)
    return el.identifier
  end
  details_counter = details_counter + 1
  local id = string.format("details-%d", details_counter)
  debug_log("Generated ID: '%s'", id)
  return id
end

-- ============================================================================
-- HTML Output Generation
-- ============================================================================

--- Determines the open state for an HTML details element.
--- Checks the element's open attribute, falling back to global default.
---@param el pandoc.Div The details Div element
---@return boolean open True if the details should be open by default
local function get_html_open_state(el)
  local attr_open = el.attributes.open

  if attr_open == "true" or attr_open == "" then
    return true
  elseif attr_open == "false" then
    return false
  else
    return interactive_opts.open
  end
end

--- Builds an HTML attributes string from an ordered list of name-value pairs.
--- Handles boolean attributes (true = present, false = absent) and string values.
--- A list rather than a keyed table keeps the attribute order stable between renders.
---@param attrs [string, string|boolean][] Ordered {name, value} pairs
---@return string attributes Space-separated HTML attributes string
local function build_html_attributes(attrs)
  local parts = {}
  for _, attr in ipairs(attrs) do
    local name, value = attr[1], attr[2]
    if value == true then
      table.insert(parts, name)
    elseif type(value) == "string" then
      table.insert(parts, string.format('%s="%s"', name, escape_html(value)))
    end
  end
  return table.concat(parts, " ")
end

--- Generates HTML output for a details element.
--- Creates the `<details>` and `<summary>` HTML wrapper while preserving
--- summary and content as Pandoc elements for proper Quarto processing (math, etc.).
---@param summary DetailsSummary The element's summary
---@param content pandoc.List The content blocks to render inside the details
---@param attrs [string, string|boolean][] Ordered {name, value} pairs of HTML attributes
---@return pandoc.List blocks RawBlocks for the wrapper around the preserved content blocks
local function generate_html(summary, content, attrs)
  local attr_str = build_html_attributes(attrs)
  if attr_str ~= "" then
    attr_str = " " .. attr_str
  end

  local result = pandoc.List()

  -- Opening details tag
  result:insert(pandoc.RawBlock('html', string.format('<details%s>', attr_str)))

  -- Summary inlines between raw <summary> tags
  local summary_inlines = pandoc.Inlines({ pandoc.RawInline('html', '<summary>') })
  summary_inlines:extend(summary.inlines or text_to_summary_inlines(summary.plain))
  summary_inlines:insert(pandoc.RawInline('html', '</summary>'))
  result:insert(pandoc.Plain(summary_inlines))

  -- Preserve content as Pandoc blocks for proper Quarto processing
  result:extend(content)

  -- Closing details tag
  result:insert(pandoc.RawBlock('html', '</details>'))

  return result
end

--- Processes a details div for HTML output.
--- Builds the complete HTML structure with accessibility attributes and accordion support.
--- The div's own classes and other attributes are passed through to the details element.
---@param el pandoc.Div The details Div element
---@param summary DetailsSummary The element's summary
---@param content pandoc.List The cleaned content blocks
---@return pandoc.List blocks The details element as Pandoc blocks
local function process_html(el, summary, content)
  local id = get_element_id(el)
  local is_open = get_html_open_state(el)
  local group = el.attributes.group
  local accordion_mode = element_option(el, "accordion-mode", interactive_opts.accordion_mode, ACCORDION_MODES)

  -- Build attributes list (ordered, so output is stable between renders)
  ---@type [string, string|boolean][]
  local attrs = {
    { "id", id },
    { "class", table.concat(el.classes, " ") },
    { "open", is_open },
    { "aria-label", summary.plain }
  }

  -- Handle accordion grouping based on mode
  if group then
    if accordion_mode == "exclusive" then
      -- Use native HTML name attribute for exclusive mode
      table.insert(attrs, { "name", group })
    else
      -- Use data attribute for synchronized mode (handled by JavaScript)
      table.insert(attrs, { "data-details-group", group })
      table.insert(attrs, { "data-accordion-mode", "synchronized" })
      has_synchronized_groups = true
    end
  end

  -- Pass the div's other attributes through, in source order
  for name, value in pairs(el.attributes) do
    if not OPTION_ATTRIBUTES[name] then
      table.insert(attrs, { name, value })
    end
  end

  debug_log("Processing HTML: id=%s, open=%s, group=%s, mode=%s",
    id, tostring(is_open), tostring(group), accordion_mode)

  return generate_html(summary, content, attrs)
end

-- ============================================================================
-- Non-Interactive Output Generation
-- ============================================================================

--- Creates a Quarto callout block.
--- Quarto's callout renderers keep only cross-reference IDs (such as `nte-`),
--- so a custom ID goes on a wrapping Div, which every writer turns into an anchor.
---@param title string|pandoc.Inlines The callout title
---@param content pandoc.List The callout content blocks
---@param callout_type string The callout type (note, warning, tip, caution, important)
---@param id string Custom ID for the callout, or "" for none
---@return pandoc.Block callout Quarto Callout block, wrapped in a Div when an ID is given
local function create_callout(title, content, callout_type, id)
  local callout = quarto.Callout({
    type = callout_type,
    title = title,
    content = pandoc.Blocks(content),
    collapse = false
  }) --[[@as pandoc.Block]]
  if id == "" then
    return callout
  end
  return pandoc.Div({ callout }, pandoc.Attr(id))
end

--- Processes a details div for non-interactive output.
--- Creates a Quarto callout or removes the element based on display mode.
---@param el pandoc.Div The details Div element
---@param summary DetailsSummary The element's summary
---@param content pandoc.List The cleaned content blocks
---@return pandoc.Block|table output Quarto Callout block, or an empty table (for removal)
local function process_non_interactive(el, summary, content)
  local display = element_option(el, "display", non_interactive_opts.display, DISPLAY_MODES)

  debug_log("Processing non-interactive: display=%s", display)

  if display == "remove" then
    debug_log("Removing details block")
    return {}
  end

  local callout_type = element_option(el, "callout-type", non_interactive_opts.callout_type)
  -- An explicit non-interactive summary overrides the summary used in HTML.
  -- Rich summaries keep their inlines, so math and cross-references render in the title.
  local title = el.attributes["non-interactive-summary"] or summary.inlines or summary.plain
  -- Only an author-supplied ID is kept; generated IDs exist for HTML only
  local id = el.identifier

  if display == "placeholder" then
    local placeholder = element_option(el, "placeholder-text", non_interactive_opts.placeholder_text)
    debug_log("Creating placeholder callout: '%s'", placeholder)
    return create_callout(title, pandoc.List({ pandoc.Para(pandoc.Str(placeholder)) }), callout_type, id)
  end

  -- display == "show"
  debug_log("Creating full callout with title: '%s'", pandoc.utils.stringify(title))
  return create_callout(title, content, callout_type, id)
end

--- Processes a details Div element.
--- Main entry point for handling a details block. Extracts the summary and
--- delegates to the format-specific processor.
---@param el pandoc.Div The Div element with the "details" class
---@return pandoc.List|pandoc.Block|table output Processed output: details blocks (HTML), Callout, or empty table
local function process_details_div(el)
  debug_log("Processing details div")

  -- Track that we have at least one details element
  has_details_elements = true

  local default_summary = is_interactive and interactive_opts.summary_text or non_interactive_opts.summary_text
  local summary, content = extract_summary(el, default_summary)

  if is_interactive then
    return process_html(el, summary, content)
  end

  return process_non_interactive(el, summary, content)
end

-- ============================================================================
-- JavaScript Generation
-- ============================================================================

--- JavaScript for synchronized accordion groups.
--- Listens for toggle events and synchronizes all details elements in the same group.
local SYNCHRONIZED_JS = [[
<script>
(function() {
  document.addEventListener('DOMContentLoaded', function() {
    // Find all synchronized details elements
    var syncDetails = document.querySelectorAll('details[data-accordion-mode="synchronized"]');
    
    syncDetails.forEach(function(details) {
      details.addEventListener('toggle', function(e) {
        if (e.target !== details) return;
        
        var group = details.getAttribute('data-details-group');
        if (!group) return;
        
        var isOpen = details.open;
        
        // Update all other details in the same group. Comparing the
        // attribute avoids building a selector from the group name.
        syncDetails.forEach(function(member) {
          if (member !== details &&
              member.getAttribute('data-details-group') === group &&
              member.open !== isOpen) {
            member.open = isOpen;
          }
        });
      });
    });
  });
})();
</script>
]]

-- ============================================================================
-- Expand/Collapse Controls
-- ============================================================================

--- CSS for the expand/collapse controls.
--- Provides styling for the control buttons with hover, focus, and active states.
local CONTROLS_CSS = [[
<style>
.details-controls {
  display: flex;
  gap: 0.5rem;
  margin: 1rem 0;
  flex-wrap: wrap;
}
.details-controls button {
  padding: 0.375rem 0.75rem;
  font-size: 0.875rem;
  font-weight: 500;
  border: 1px solid #d1d5db;
  border-radius: 0.375rem;
  background-color: #f9fafb;
  color: #374151;
  cursor: pointer;
  transition: background-color 0.15s ease-in-out, border-color 0.15s ease-in-out;
}
.details-controls button:hover {
  background-color: #f3f4f6;
  border-color: #9ca3af;
}
.details-controls button:focus {
  outline: 2px solid #3b82f6;
  outline-offset: 2px;
}
.details-controls button:active {
  background-color: #e5e7eb;
}
</style>
]]

--- JavaScript for the expand/collapse control buttons.
--- Defines global functions for expanding and collapsing all details elements
--- created by this extension (`details.details`), leaving others such as
--- Quarto's code-fold blocks alone.
local CONTROLS_JS = [[
<script>
(function() {
  window.detailsExpandAll = function() {
    document.querySelectorAll('details.details').forEach(function(details) {
      details.open = true;
    });
  };
  
  window.detailsCollapseAll = function() {
    document.querySelectorAll('details.details').forEach(function(details) {
      details.open = false;
    });
  };
})();
</script>
]]

--- Generates the expand/collapse controls.
--- Creates a button group with expand all and collapse all buttons.
--- Includes ARIA attributes for accessibility.
---@param position "top"|"bottom" Position identifier used in the element ID
---@return pandoc.RawBlock controls HTML for the control buttons
local function controls_block(position)
  local expand_text = escape_html(interactive_opts.controls_expand_text)
  local collapse_text = escape_html(interactive_opts.controls_collapse_text)

  return pandoc.RawBlock('html', string.format([[
<div class="details-controls" id="details-controls-%s" role="group" aria-label="Expand or collapse all details sections">
  <button type="button" onclick="window.detailsExpandAll()" aria-label="%s">%s</button>
  <button type="button" onclick="window.detailsCollapseAll()" aria-label="%s">%s</button>
</div>
]], position, expand_text, expand_text, collapse_text, collapse_text))
end

-- ============================================================================
-- Pandoc Filter Entry Points
-- ============================================================================

--- Div filter: processes details divs and conditional content.
--- Handles both details blocks and conditional content divs.
---@param el pandoc.Div The Div element to process
---@return pandoc.List|pandoc.Block|table|nil output Processed output, or nil if the element is unchanged
local function process_div(el)
  -- Check for details div first
  if el.classes:includes('details') then
    return process_details_div(el)
  end

  -- Check for conditional content
  return process_conditional_div(el)
end

--- Pandoc filter: injects controls and JavaScript into the document.
--- Runs after all Div processing to add document-level features. The CSS
--- and JavaScript go in the page header and after the body, not in the
--- body, so that RevealJS doesn't turn them into a slide of their own.
---@param doc pandoc.Pandoc The Pandoc document
---@return pandoc.Pandoc doc The document with the controls added
local function add_document_features(doc)
  if not is_interactive then
    return doc
  end

  -- Handle expand/collapse controls
  if interactive_opts.show_controls and has_details_elements then
    debug_log("Injecting expand/collapse controls")

    quarto.doc.include_text("in-header", CONTROLS_CSS)
    quarto.doc.include_text("after-body", CONTROLS_JS)

    local position = interactive_opts.controls_position

    if position ~= "bottom" then
      debug_log("Adding controls at top")
      -- RevealJS turns blocks before the first heading into an untitled slide,
      -- so the top controls go under the first slide's heading instead
      local first = doc.blocks[1]
      local at = 1
      if quarto.doc.is_format("revealjs") and first and first.t == "Header" then
        at = 2
      end
      doc.blocks:insert(at, controls_block("top"))
    end

    if position ~= "top" then
      debug_log("Adding controls at bottom")
      doc.blocks:insert(controls_block("bottom"))
    end
  end

  -- Handle synchronized accordion groups
  if has_synchronized_groups then
    debug_log("Injecting JavaScript for synchronized accordion groups")
    quarto.doc.include_text("after-body", SYNCHRONIZED_JS)
  end

  return doc
end

--- Filter chain registration.
--- Meta runs first to read the options, then Div for each element, then
--- Pandoc for document-level features.
return {
  { Meta = initialize_options },
  { Div = process_div },
  { Pandoc = add_document_features }
}
