.PHONY: test deps clean lint

NVIM ?= nvim

deps:
	@mkdir -p deps
	@if [ ! -d deps/mini.nvim ]; then \
		git clone --depth 1 https://github.com/echasnovski/mini.nvim deps/mini.nvim; \
	fi

test: deps
	$(NVIM) --headless -u scripts/minimal_init.lua -c "lua MiniTest.run()"

test-file: deps
	$(NVIM) --headless -u scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"

lint:
	luacheck lua/ --globals vim

clean:
	rm -rf deps
