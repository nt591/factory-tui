local function project_root(path)
  return vim.fs.root(path, { "dune-project", "dune-workspace", ".git" }) or vim.fn.getcwd()
end

local function opam_command(root, tool)
  local command = { "opam", "exec" }
  if vim.uv.fs_stat(root .. "/_opam") then
    command[#command + 1] = "--switch=" .. root
  end
  vim.list_extend(command, { "--", tool })
  return command
end

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        ocamllsp = {
          mason = false,
          filetypes = { "ocaml", "ocamlinterface", "menhir", "ocamllex", "reason", "dune" },
          root_markers = { "dune-project", "dune-workspace", ".git" },
          cmd = function(dispatchers, config)
            local root = config.root_dir or vim.fn.getcwd()
            return vim.lsp.rpc.start(opam_command(root, "ocamllsp"), dispatchers, { cwd = root })
          end,
        },
      },
    },
  },
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        ocaml = { "ocamlformat" },
        ocamlinterface = { "ocamlformat" },
      },
      formatters = {
        ocamlformat = {
          command = "opam",
          prepend_args = function(_, ctx)
            local command = opam_command(project_root(ctx.filename), "ocamlformat")
            table.remove(command, 1)
            return command
          end,
          cwd = function(_, ctx)
            return project_root(ctx.filename)
          end,
        },
      },
    },
  },
}
