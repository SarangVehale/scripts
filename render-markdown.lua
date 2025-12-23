-- lua/plugins/markdown-suite.lua
-- The definitive "Outrageous" configuration for render-markdown.nvim.
-- This is a complete, copy-paste-ready file.

return {
	"MeanderingProgrammer/render-markdown.nvim",
	name = "render-markdown",
	dependencies = { "nvim-treesitter/nvim-treesitter" },
	ft = { "markdown" },
	opts = function()
		-- ===================================================================
		-- HELPER FUNCTIONS FOR DYNAMIC RENDERING
		-- ===================================================================
		local function format_size(size)
			if not size then
				return "N/A"
			end
			if size > 1024 * 1024 then
				return string.format("%.1fMB", size / (1024 * 1024))
			end
			if size > 1024 then
				return string.format("%.1fKB", size / 1024)
			end
			return tostring(size) .. "B"
		end

		local function format_time_ago(mod_time)
			if not mod_time then
				return "N/A"
			end
			local diff = os.time() - mod_time
			if diff < 60 then
				return "now"
			end
			if diff < 3600 then
				return math.floor(diff / 60) .. "m ago"
			end
			if diff < 86400 then
				return math.floor(diff / 3600) .. "h ago"
			end
			return math.floor(diff / 86400) .. "d ago"
		end

		return {
			-- ===================================================================
			-- 1. HEADERS: Maximize Visual Hierarchy
			-- ===================================================================
			head = {
				enabled = true,
				icons = { "󰎤 ", "󰎧 ", "󰎪 ", "󰎭 ", "󰎱 ", "󰎳 " },
				highlight = "RenderMarkdownHeading",
				render_method = "inline",
			},

			-- ===================================================================
			-- 2. LINKS: Dynamic, Context-Aware, and Informative
			-- ===================================================================
			link = {
				enabled = true,
				render_modes = false,
				footnote = { enabled = true, superscript = true, prefix = " ", suffix = "" },
				image = "󰥶 ",
				email = "󰀓 ",
				hyperlink = "󰌹 ",
				highlight = "RenderMarkdownLink",
				-- FEATURE: The "Living" WikiLink
				wiki = {
					icon = "", -- We provide our own icon within the body function
					highlight = "RenderMarkdownWikiLink",
					body = function(ctx)
						-- IMPORTANT: Adjust this path to your notes directory!
						local notes_path = vim.fn.expand("~/notes")
						local file_path = notes_path .. ctx.value .. ".md"

						if vim.fn.filereadable(file_path) == 1 then
							local stat = vim.loop.fs_stat(file_path)
							local size_str = format_size(stat and stat.size)
							local time_str = format_time_ago(stat and stat.mtime.sec)
							return string.format("󱗖 %s | 󰥔 %s", size_str, time_str)
						else
							return "󰅖 Missing"
						end
					end,
				},
				-- Hyper-specific link icons for your fields
				custom = {
					web = { pattern = "^http", icon = "󰖟 " },
					github = { pattern = "github%.com", icon = "󰊤 " },
					gitlab = { pattern = "gitlab%.com", icon = "󰮠 " },
					stackoverflow = { pattern = "stackoverflow%.com", icon = "󰓌 " },
					wikipedia = { pattern = "wikipedia%.org", icon = "󰖬 " },
					youtube = { pattern = "youtube%.com", icon = "󰗃 " },
					arxiv = { pattern = "arxiv%.org", icon = "󰎠 " },
					wolframalpha = { pattern = "wolframalpha%.com", icon = "󰐴 " },
					overleaf = { pattern = "overleaf%.com", icon = "󰂊 " },
					crates_io = { pattern = "crates%.io", icon = "󰎘 " },
					docs_rs = { pattern = "docs%.rs", icon = "󰎘 " },
					pypi = { pattern = "pypi%.org", icon = "󰠠 " },
					npm = { pattern = "npmjs%.com", icon = "󰎙 " },
					dev_docs = { pattern = "devdocs%.io", icon = "󰡩 " },
					mdn = { pattern = "developer%.mozilla%.org", icon = "󰜫 " },
					owasp = { pattern = "owasp%.org", icon = "󰓮 " },
					portswigger = { pattern = "portswigger%.net", icon = "󰋳 " },
					cve = { pattern = "cve%.mitre%.org", icon = "󰛵 " },
				},
			},

			-- ===================================================================
			-- 3. CALLOUTS: Semantic Workflows and Advanced Tagging
			-- ===================================================================
			callout = {
				-- Standard Admonitions
				note = { raw = "[!NOTE]", rendered = "󰋽 Note", highlight = "RenderMarkdownInfo" },
				tip = { raw = "[!TIP]", rendered = "󰌶 Tip", highlight = "RenderMarkdownSuccess" },
				important = { raw = "[!IMPORTANT]", rendered = "󰅾 Important", highlight = "RenderMarkdownHint" },
				warning = { raw = "[!WARNING]", rendered = "󰀪 Warning", highlight = "RenderMarkdownWarn" },
				caution = { raw = "[!CAUTION]", rendered = "󰳦 Caution", highlight = "RenderMarkdownError" },
				-- Extended Admonitions
				abstract = { raw = "[!ABSTRACT]", rendered = "󰨸 Abstract", highlight = "RenderMarkdownInfo" },
				summary = { raw = "[!SUMMARY]", rendered = "󰨸 Summary", highlight = "RenderMarkdownInfo" },
				tldr = { raw = "[!TLDR]", rendered = "󰨸 Tldr", highlight = "RenderMarkdownInfo" },
				info = { raw = "[!INFO]", rendered = "󰋽 Info", highlight = "RenderMarkdownInfo" },
				todo = { raw = "[!TODO]", rendered = "󰗡 Todo", highlight = "RenderMarkdownInfo" },
				success = { raw = "[!SUCCESS]", rendered = "󰄬 Success", highlight = "RenderMarkdownSuccess" },
				question = { raw = "[!QUESTION]", rendered = "󰘥 Question", highlight = "RenderMarkdownWarn" },
				failure = { raw = "[!FAILURE]", rendered = "󰅖 Failure", highlight = "RenderMarkdownError" },
				danger = { raw = "[!DANGER]", rendered = "󱐌 Danger", highlight = "RenderMarkdownError" },
				bug = { raw = "[!BUG]", rendered = "󰨰 Bug", highlight = "RenderMarkdownError" },
				example = { raw = "[!EXAMPLE]", rendered = "󰉹 Example", highlight = "RenderMarkdownHint" },
				quote = { raw = "[!QUOTE]", rendered = "󱆨 Quote", highlight = "RenderMarkdownQuote" },
				-- Math & Science
				definition = { raw = "[!DEF]", rendered = "󰙰 Definition", highlight = "RenderMarkdownHint" },
				theorem = { raw = "[!THM]", rendered = "󰔷 Theorem", highlight = "RenderMarkdownSuccess" },
				proof = { raw = "[!PROOF]", rendered = "󰋺 Proof", highlight = "RenderMarkdownInfo" },
				-- Quantum Computing
				qbit = { raw = "[!QBIT]", rendered = "󰀫 Qubit", highlight = "RenderMarkdownInfo" },
				superpos = { raw = "[!SUPERPOS]", rendered = "󰀫 Superposition", highlight = "RenderMarkdownHint" },
				entangle = { raw = "[!ENTANGLE]", rendered = "󰌷 Entanglement", highlight = "RenderMarkdownSuccess" },
				measure = { raw = "[!MEASURE]", rendered = "󰄬 Measurement", highlight = "RenderMarkdownWarn" },
				-- Cyber Kill Chain
				recon = { raw = "[!RECON]", rendered = "󰄛 1. Recon", highlight = "RenderMarkdownInfo" },
				weaponize = { raw = "[!WEAPONIZE]", rendered = "󰆽 2. Weaponize", highlight = "RenderMarkdownHint" },
				deliver = { raw = "[!DELIVER]", rendered = "󰇙 3. Deliver", highlight = "RenderMarkdownWarn" },
				exploit = { raw = "[!EXPLOIT]", rendered = "󰯐 4. Exploit", highlight = "RenderMarkdownError" },
				install = { raw = "[!INSTALL]", rendered = "󰋼 5. Install", highlight = "RenderMarkdownError" },
				c2 = { raw = "[!C2]", rendered = "󰒑 6. C2", highlight = "RenderMarkdownError" },
				action = { raw = "[!ACTION]", rendered = "󰊘 7. Action", highlight = "RenderMarkdownError" },
				-- Code Annotation
				deprecated = { raw = "[!DEPRECATED]", rendered = "󰅚 Deprecated", highlight = "Comment" },
				optimal = { raw = "[!OPTIMAL]", rendered = "󰌶 Optimal", highlight = "RenderMarkdownSuccess" },
				secure_code = { raw = "[!SECURE]", rendered = "󰒃 Secure", highlight = "RenderMarkdownSuccess" },
				vulnerable_code = {
					raw = "[!VULN-CODE]",
					rendered = "󰅖 Vulnerable",
					highlight = "RenderMarkdownError",
				},
			},

			-- ===================================================================
			-- 4. CHECKBOXES: The "Kanban" System
			-- ===================================================================
			checkbox = {
				enabled = true,
				unchecked = { icon = "󰄱 ", highlight = "RenderMarkdownUnchecked" },
				checked = { icon = "󰱒 ", highlight = "RenderMarkdownChecked" },
				custom = {
					in_progress = { raw = "[-]", rendered = "󰥔 ", highlight = "RenderMarkdownTodo" },
					cancelled = { raw = "[~]", rendered = "󰰱 ", highlight = "Comment" },
					blocked = { raw = "[b]", rendered = "󰹆 ", highlight = "RenderMarkdownError" },
					delegated = { raw = "[d]", rendered = "󰆴 ", highlight = "RenderMarkdownHint" },
					question = { raw = "[?]", rendered = "󰘥 ", highlight = "RenderMarkdownWarn" },
					idea = { raw = "[i]", rendered = "󰌶 ", highlight = "RenderMarkdownSuccess" },
				},
			},

			-- ===================================================================
			-- 5. BULLETS: The "Contextual" List
			-- ===================================================================
			bullet = {
				enabled = true,
				icons = { "●", "○", "◆", "◇" },
				highlight = "RenderMarkdownBullet",
				-- NEW, ROBUST CODE
				ordered_icons = function(ctx)
					-- GUARD CLAUSE: Check if ctx.line is a valid string before using it.
					if type(ctx.line) == "string" then
						if string.find(ctx.line, "DUE:") then
							return "󰥔 "
						elseif string.find(ctx.line, "DONE:") then
							return "󰱒 "
						elseif string.find(ctx.line, "BLOCKED:") then
							return "󰹆 "
						end
					end
					-- Fallback to default logic if the line is nil or doesn't match keywords
					local roman = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }
					if ctx.index and ctx.index <= 10 then
						return roman[ctx.index] .. "."
					end
					if ctx.index then
						return ("%d."):format(ctx.index)
					end
					return "•" -- Absolute fallback
				end,
			},

			-- ===================================================================
			-- 6. CODE BLOCKS: Enhanced Readability & Usability
			-- ===================================================================
			code = {
				enabled = true,
				language = { enabled = true, highlight = "RenderMarkdownCodeLanguage" },
				background = true,
				background_highlight = "RenderMarkdownCodeBg",
				copy_button = {
					enabled = true,
					icon = "󰆏",
					highlight = "RenderMarkdownCopyButton",
					clipboard = true,
				},
			},

			-- ===================================================================
			-- 7. INLINE CODE: Distinct Snippet Styling
			-- ===================================================================
			inline_code = {
				enabled = true,
				highlight = "RenderMarkdownInlineCode",
				background = true,
				background_highlight = "RenderMarkdownInlineCodeBg",
			},

			-- ===================================================================
			-- 8. TABLES, RULES, QUOTES: Maximum Aesthetic Polish
			-- ===================================================================
			table = {
				enabled = true,
				border = { "│", "─", "┌", "┐", "└", "┘", "├", "┤", "┬", "┴", "┼" },
				highlight = "RenderMarkdownTableBorder",
				background = true,
				background_highlight = "RenderMarkdownTableBg",
			},
			dash = {
				enabled = true,
				char = "─",
				highlight = "RenderMarkdownDash",
			},
			quote = {
				enabled = true,
				icon = "▋",
				highlight = "RenderMarkdownQuote",
				background = true,
				background_highlight = "RenderMarkdownQuoteBg",
			},

			-- ===================================================================
			-- 9. ANTI-CONCEAL: Fine-Tuned Control
			-- ===================================================================
			anti_conceal = {
				enabled = true,
				ignore = {
					code_background = true,
					table_border = true,
					sign = true,
				},
				above = 0,
				below = 0,
			},
		}
	end,
}
