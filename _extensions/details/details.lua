-- Global variables to store extension options
local default_open = false
local default_summary_text = "Click to expand"

-- Read options from metadata
function Meta(meta)
  if meta.extensions and meta.extensions.details then
    local details_opts = meta.extensions.details
    
    -- Check for open option
    if details_opts.open then
      default_open = details_opts.open
    end
    
    -- Check for summary-text option
    if details_opts['summary-text'] then
      default_summary_text = pandoc.utils.stringify(details_opts['summary-text'])
    end
  end
  
  return meta
end

function Div(el)
  -- Check if this is a details div
  if el.classes:includes('details') then
    local summary_text = default_summary_text
    local content = {}
    local summary_source = "default"
    
    -- Priority 1: Look for summary attribute
    if el.attributes.summary then
      summary_text = el.attributes.summary
      summary_source = "attribute"
    end
    
    -- Priority 2: Look for nested summary div (always remove from content)
    if summary_source == "default" then
      for i, block in ipairs(el.content) do
        if block.t == "Div" and block.classes:includes('summary') then
          summary_text = pandoc.utils.stringify(block.content)
          summary_source = "div"
          -- Remove summary div from content
          table.remove(el.content, i)
          break
        end
      end
    else
      -- Even if not using as summary, remove summary div from content
      for i, block in ipairs(el.content) do
        if block.t == "Div" and block.classes:includes('summary') then
          table.remove(el.content, i)
          break
        end
      end
    end
    
    -- Priority 3: Look for first heading as summary (only remove if using as summary)
    if summary_source == "default" then
      for i, block in ipairs(el.content) do
        if block.t == "Header" then
          summary_text = pandoc.utils.stringify(block.content)
          summary_source = "heading"
          -- Remove heading from content only when using it as summary
          table.remove(el.content, i)
          break
        end
      end
    end
    
    -- Check for open attribute (instance-level overrides global)
    local open_attr = ""
    if el.attributes.open == "true" or el.attributes.open == "" then
      open_attr = " open"
    elseif el.attributes.open == "false" then
      open_attr = ""
    elseif default_open then
      open_attr = " open"
    end
    
    -- Build the HTML
    local html = string.format(
      '<details%s>\n<summary>%s</summary>\n',
      open_attr,
      summary_text
    )
    
    -- Convert content to HTML
    local body = pandoc.write(pandoc.Pandoc(el.content), 'html')
    html = html .. body .. '\n</details>'
    
    return pandoc.RawBlock('html', html)
  end
end

-- Return filters with Meta before Div
return {
  { Meta = Meta },
  { Div = Div }
}