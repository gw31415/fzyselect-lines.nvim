--------------------------------------
-- From snacks.nvim by folke
-- Apache License 2.0
--------------------------------------
-- https://github.com/folke/snacks.nvim/blob/b100c937177536cf2aa634ddd2aa5b8a1dd23ace/lua/snacks/picker/util/highlight.lua#L6-L106
local langs = {}
local function get_highlights(opts)
	local function get_lang(opts2)
		opts2 = opts2 or {}
		local lang = opts2.lang or (opts2.ft and vim.treesitter.language.get_lang(opts2.ft)) or nil
		if not lang then
			return
		end
		if langs[lang] == nil then
			langs[lang] = pcall(vim.treesitter.language.add, lang)
		end
		return langs[lang] and lang or nil
	end

	opts = opts or {}
	local source = assert(opts.buf or opts.code, 'buf or code is required')
	assert(not (opts.buf and opts.code), 'only one of buf or code is allowed')

	local ret = {}

	local ft = opts.ft
	    or (opts.buf and vim.bo[opts.buf].filetype)
	    or (opts.file and vim.filetype.match { filename = opts.file, buf = 0 })
	    or vim.bo.filetype
	local lang = get_lang { lang = opts.lang, ft = ft }
	local parser ---@type vim.treesitter.LanguageTree?
	if lang then
		lang = lang:lower()
		local ok = false
		if opts.buf then
			ok, parser = pcall(vim.treesitter.get_parser, opts.buf, lang)
		else
			ok, parser = pcall(vim.treesitter.get_string_parser, source, lang)
		end
		parser = ok and parser or nil
	end

	if parser then
		parser:parse(true)
		parser:for_each_tree(function(tstree, tree)
			if not tstree then
				return
			end
			local query = vim.treesitter.query.get(tree:lang(), 'highlights')
			-- Some injected languages may not have highlight queries.
			if not query then
				return
			end

			for capture, node, metadata in query:iter_captures(tstree:root(), source) do
				---@type string
				local name = query.captures[capture]
				if name ~= 'spell' then
					local range = { node:range() } ---@type number[]
					local multi = range[1] ~= range[3]
					local text = multi
					    and vim.split(vim.treesitter.get_node_text(node, source, metadata[capture]),
						    '\n',
						    { plain = true })
					    or {}
					for row = range[1] + 1, range[3] + 1 do
						local first, last = row == range[1] + 1, row == range[3] + 1
						local end_col = last and range[4] or #(text[row - range[1]] or '')
						end_col = multi and first and end_col + range[2] or end_col
						ret[row] = ret[row] or {}
						table.insert(ret[row], {
							col = first and range[2] or 0,
							end_col = end_col,
							priority = (tonumber(metadata.priority or metadata[capture] and metadata[capture].priority) or 100),
							conceal = metadata.conceal or
							    metadata[capture] and metadata[capture].conceal,
							hl_group = '@' .. name .. '.' .. lang,
						})
					end
				end
			end
		end)
	end

	return ret
end

--------------------------------------
-- End of copied code
--------------------------------------

return {
	open = function()
		local winid = vim.api.nvim_get_current_win()
		local tabstop = vim.api.nvim_get_option_value('tabstop', {})
		local shiftwidth = vim.api.nvim_get_option_value('shiftwidth', {})
		local col = 0
		local ns_id = vim.api.nvim_create_namespace 'fzyselect_lines_highlights'
		local extmarklines = vim.deepcopy(get_highlights { buf = vim.api.nvim_get_current_buf(), extmarks = true })

		vim.api.nvim_create_autocmd('FileType', {
			callback = function()
				vim.api.nvim_set_option_value('tabstop', tabstop, {})
				vim.api.nvim_set_option_value('shiftwidth', shiftwidth, {})
				vim.api.nvim_create_autocmd({ 'TextChanged', 'WinScrolled' }, {
					buffer = 0,
					callback = function()
						vim.api.nvim_buf_clear_namespace(0, ns_id, 0, -1)
						for fzyl = vim.fn.line 'w0', vim.fn.line 'w$' do
							local item = require 'fzyselect'.getitem(fzyl)
							if item ~= vim.NIL then
								local _, origline = unpack(item)
								for _, extmark in ipairs(extmarklines[origline] or {}) do
									if extmark.col then
										local startcol = extmark.col
										local e = vim.deepcopy(extmark)
										e.col = nil
										vim.api.nvim_buf_set_extmark(0, ns_id,
											fzyl - 1, startcol, e)
									end
								end
							end
						end
					end
				})
				vim.api.nvim_create_autocmd('CursorMoved', {
					buffer = 0,
					callback = function()
						_, col = unpack(vim.api.nvim_win_get_cursor(0))
					end,
				})
			end,
			pattern = 'fzyselect',
			once = true,
		})
		require 'fzyselect'.start(vim.api.nvim_buf_get_lines(0, 0, -1, true),
			{ prompt = 'fuzzy search: <Enter> to jump' },
			function(_, i)
				if i then
					vim.api.nvim_win_set_cursor(winid, { i, col })
				end
			end)
	end
}
