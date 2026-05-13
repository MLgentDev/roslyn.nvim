local helpers = require("test.utils.helpers")

local function cmd_contains(cmd, value)
    for _, entry in ipairs(cmd) do
        if entry == value then
            return true
        end
    end
    return false
end

local function cmd_has_prefix(cmd, prefix)
    for _, entry in ipairs(cmd) do
        if type(entry) == "string" and vim.startswith(entry, prefix) then
            return true
        end
    end
    return false
end

helpers.env()

describe("lsp cmd", function()
    local function capture_cmd(callback)
        return helpers.exec_lua(function(cb)
            local captured_cmd
            vim.lsp.rpc = vim.lsp.rpc or {}
            vim.lsp.rpc.start = function(c)
                captured_cmd = c
                return {}
            end

            local cleanup = cb()

            local cwd = vim.uv.cwd()
            local lsp_config = dofile(vim.fs.joinpath(cwd, "lsp", "roslyn.lua"))
            lsp_config.cmd({}, { cmd_cwd = nil, cmd_env = nil, detached = nil })
            if cleanup then
                cleanup()
            end
            return captured_cmd
        end, callback)
    end

    after_each(function()
        helpers.exec_lua(function()
            package.loaded["roslyn.config"] = nil
            package.loaded["roslyn.utils"] = nil
            require("roslyn.config")
            require("roslyn.utils")
        end)
    end)

    before_each(function()
        helpers.clear()
        helpers.exec_lua("package.path = ...", package.path)
    end)

    it("adds extension path and args when provided", function()
        local cmd = capture_cmd(function()
            require("roslyn.config").setup({
                extensions = {
                    razor = { enabled = false },
                    testext = {
                        enabled = true,
                        config = {
                            path = "/tmp/roslyn-test-extension.dll",
                            args = { "--foo=bar", "--baz" },
                        },
                    },
                },
            })
        end)

        assert.is_true(cmd_contains(cmd, "--extension=/tmp/roslyn-test-extension.dll"))
        assert.is_true(cmd_contains(cmd, "--foo=bar"))
        assert.is_true(cmd_contains(cmd, "--baz"))
    end)

    it("skips extension when no path is provided", function()
        local cmd = capture_cmd(function()
            require("roslyn.config").setup({
                extensions = {
                    razor = { enabled = false },
                    testext = {
                        enabled = true,
                        config = { path = nil },
                    },
                },
            })
        end)

        assert.is_false(cmd_has_prefix(cmd, "--extension="))
    end)

    it("supports extension config as function", function()
        local cmd = capture_cmd(function()
            require("roslyn.config").setup({
                extensions = {
                    razor = { enabled = false },
                    testext = {
                        enabled = true,
                        config = function()
                            return {
                                path = "/tmp/roslyn-test-extension-fn.dll",
                                args = { "--alpha", "--beta=1" },
                            }
                        end,
                    },
                },
            })
        end)

        assert.is_true(cmd_contains(cmd, "--extension=/tmp/roslyn-test-extension-fn.dll"))
        assert.is_true(cmd_contains(cmd, "--alpha"))
        assert.is_true(cmd_contains(cmd, "--beta=1"))
    end)

    it("prefers roslyn-language-server when available", function()
        local cmd = capture_cmd(function()
            local original_executable = vim.fn.executable
            vim.fn.executable = function(value)
                if value == "roslyn-language-server" then
                    return 1
                end
                return 0
            end

            return function()
                vim.fn.executable = original_executable
            end
        end)

        assert.are.equal("roslyn-language-server", cmd[1])
    end)

    it("falls back to mason roslyn when the global tool is unavailable", function()
        local cmd = capture_cmd(function()
            local utils = require("roslyn.utils")
            local original_executable = vim.fn.executable
            local sysname = vim.uv.os_uname().sysname:lower()
            local roslyn_bin = (sysname:find("windows") or sysname:find("mingw")) and "roslyn.cmd" or "roslyn"
            local mason_bin = vim.fs.joinpath(utils.get_mason_path(), "bin", roslyn_bin)

            vim.fn.executable = function(value)
                if value == mason_bin then
                    return 1
                end
                return 0
            end

            return function()
                vim.fn.executable = original_executable
            end
        end)

        assert.is_true(vim.endswith(cmd[1], "/bin/roslyn") or vim.endswith(cmd[1], "\\bin\\roslyn.cmd"))
    end)

    it("falls back to plain roslyn before the legacy server name", function()
        local cmd = capture_cmd(function()
            local original_executable = vim.fn.executable
            local sysname = vim.uv.os_uname().sysname:lower()
            local roslyn_bin = (sysname:find("windows") or sysname:find("mingw")) and "roslyn.cmd" or "roslyn"

            vim.fn.executable = function(value)
                if value == roslyn_bin then
                    return 1
                end
                return 0
            end

            return function()
                vim.fn.executable = original_executable
            end
        end)

        assert.is_true(cmd[1] == "roslyn" or cmd[1] == "roslyn.cmd")
    end)

    it("falls back to Microsoft.CodeAnalysis.LanguageServer last", function()
        local cmd = capture_cmd(function()
            local original_executable = vim.fn.executable
            vim.fn.executable = function()
                return 0
            end

            return function()
                vim.fn.executable = original_executable
            end
        end)

        assert.are.equal("Microsoft.CodeAnalysis.LanguageServer", cmd[1])
    end)
end)
