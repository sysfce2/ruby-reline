require_relative 'helper'

class Reline::Config::Test < Reline::TestCase
  def setup
    @pwd = Dir.pwd
    @tmpdir = File.join(Dir.tmpdir, "test_reline_config_#{$$}")
    begin
      Dir.mkdir(@tmpdir)
    rescue Errno::EEXIST
      FileUtils.rm_rf(@tmpdir)
      Dir.mkdir(@tmpdir)
    end
    Dir.chdir(@tmpdir)
    Reline.test_mode
    @config = Reline::Config.new
    @inputrc_backup = ENV['INPUTRC']
  end

  def teardown
    Dir.chdir(@pwd)
    FileUtils.rm_rf(@tmpdir)
    Reline.test_reset
    @config.reset
    ENV['INPUTRC'] = @inputrc_backup
  end

  def get_config_variable(variable)
    @config.instance_variable_get(variable)
  end

  def additional_key_bindings(keymap_label)
    get_config_variable(:@additional_key_bindings)[keymap_label].instance_variable_get(:@key_bindings)
  end

  def registered_key_bindings(keys)
    key_bindings = @config.key_bindings
    keys.to_h { |key| [key, key_bindings.get(key)] }
  end

  def test_read_lines
    @config.read_lines(<<~LINES.lines)
      set show-mode-in-prompt on
    LINES

    assert_equal true, get_config_variable(:@show_mode_in_prompt)
  end

  def test_read_lines_with_variable
    @config.read_lines(<<~LINES.lines)
      set disable-completion on
    LINES

    assert_equal true, get_config_variable(:@disable_completion)
  end

  def test_string_value
    @config.read_lines(<<~LINES.lines)
      set show-mode-in-prompt on
      set emacs-mode-string Emacs
    LINES

    assert_equal 'Emacs', get_config_variable(:@emacs_mode_string)
  end

  def test_string_value_with_brackets
    @config.read_lines(<<~LINES.lines)
      set show-mode-in-prompt on
      set emacs-mode-string [Emacs]
    LINES

    assert_equal '[Emacs]', get_config_variable(:@emacs_mode_string)
  end

  def test_string_value_with_brackets_and_quotes
    @config.read_lines(<<~LINES.lines)
      set show-mode-in-prompt on
      set emacs-mode-string "[Emacs]"
    LINES

    assert_equal '[Emacs]', get_config_variable(:@emacs_mode_string)
  end

  def test_string_value_with_parens
    @config.read_lines(<<~LINES.lines)
      set show-mode-in-prompt on
      set emacs-mode-string (Emacs)
    LINES

    assert_equal '(Emacs)', get_config_variable(:@emacs_mode_string)
  end

  def test_string_value_with_parens_and_quotes
    @config.read_lines(<<~LINES.lines)
      set show-mode-in-prompt on
      set emacs-mode-string "(Emacs)"
    LINES

    assert_equal '(Emacs)', get_config_variable(:@emacs_mode_string)
  end

  def test_encoding_is_ascii
    @config.reset
    Reline.core.io_gate.instance_variable_set(:@encoding, Encoding::US_ASCII)
    @config = Reline::Config.new

    assert_equal true, @config.convert_meta
  end

  def test_encoding_is_not_ascii
    @config = Reline::Config.new

    assert_equal false, @config.convert_meta
  end

  def test_invalid_keystroke
    @config.read_lines(<<~LINES.lines)
      #"a": comment
      a: error
      "b": no-error
    LINES
    key_bindings = additional_key_bindings(:emacs)
    assert_not_include key_bindings, 'a'.bytes
    assert_not_include key_bindings, nil
    assert_not_include key_bindings, []
    assert_include key_bindings, 'b'.bytes
  end

  def test_bind_key
    assert_equal ['input'.bytes, 'abcde'.bytes], @config.parse_key_binding('"input"', '"abcde"')
  end

  def test_bind_key_with_macro

    assert_equal ['input'.bytes, :abcde], @config.parse_key_binding('"input"', 'abcde')
  end

  def test_bind_key_with_escaped_chars
    assert_equal ['input'.bytes, "\e \\ \" ' \a \b \d \f \n \r \t \v".bytes], @config.parse_key_binding('"input"', '"\\e \\\\ \\" \\\' \\a \\b \\d \\f \\n \\r \\t \\v"')
  end

  def test_bind_key_with_ctrl_chars
    assert_equal ['input'.bytes, "\C-h\C-h\C-_".bytes], @config.parse_key_binding('"input"', '"\C-h\C-H\C-_"')
    assert_equal ['input'.bytes, "\C-h\C-h\C-_".bytes], @config.parse_key_binding('"input"', '"\Control-h\Control-H\Control-_"')
  end

  def test_bind_key_with_meta_chars
    assert_equal ['input'.bytes, "\eh\eH\e_".bytes], @config.parse_key_binding('"input"', '"\M-h\M-H\M-_"')
    assert_equal ['input'.bytes, "\eh\eH\e_".bytes], @config.parse_key_binding('"input"', '"\Meta-h\Meta-H\M-_"')
  end

  def test_bind_key_with_ctrl_meta_chars
    assert_equal ['input'.bytes, "\e\C-h\e\C-h\e\C-_".bytes], @config.parse_key_binding('"input"', '"\M-\C-h\C-\M-H\M-\C-_"')
    assert_equal ['input'.bytes, "\e\C-h\e\C-_".bytes], @config.parse_key_binding('"input"', '"\Meta-\Control-h\Control-\Meta-_"')
  end

  def test_bind_key_with_octal_number
    input = %w{i n p u t}.map(&:ord)
    assert_equal [input, "\1".bytes], @config.parse_key_binding('"input"', '"\1"')
    assert_equal [input, "\12".bytes], @config.parse_key_binding('"input"', '"\12"')
    assert_equal [input, "\123".bytes], @config.parse_key_binding('"input"', '"\123"')
    assert_equal [input, "\123".bytes + '4'.bytes], @config.parse_key_binding('"input"', '"\1234"')
  end

  def test_bind_key_with_hexadecimal_number
    input = %w{i n p u t}.map(&:ord)
    assert_equal [input, "\x4".bytes], @config.parse_key_binding('"input"', '"\x4"')
    assert_equal [input, "\x45".bytes], @config.parse_key_binding('"input"', '"\x45"')
    assert_equal [input, "\x45".bytes + '6'.bytes], @config.parse_key_binding('"input"', '"\x456"')
  end

  def test_include
    File.open('included_partial', 'wt') do |f|
      f.write(<<~PARTIAL_LINES)
        set show-mode-in-prompt on
      PARTIAL_LINES
    end
    @config.read_lines(<<~LINES.lines)
      $include included_partial
    LINES

    assert_equal true, get_config_variable(:@show_mode_in_prompt)
  end

  def test_include_expand_path
    home_backup = ENV['HOME']
    File.open('included_partial', 'wt') do |f|
      f.write(<<~PARTIAL_LINES)
        set show-mode-in-prompt on
      PARTIAL_LINES
    end
    ENV['HOME'] = Dir.pwd
    @config.read_lines(<<~LINES.lines)
      $include ~/included_partial
    LINES

    assert_equal true, get_config_variable(:@show_mode_in_prompt)
  ensure
    ENV['HOME'] = home_backup
  end

  def test_if
    @config.read_lines(<<~LINES.lines)
      $if Ruby
      set vi-cmd-mode-string (cmd)
      $else
      set vi-cmd-mode-string [cmd]
      $endif
    LINES

    assert_equal '(cmd)', get_config_variable(:@vi_cmd_mode_string)
  end

  def test_if_with_false
    @config.read_lines(<<~LINES.lines)
      $if Python
      set vi-cmd-mode-string (cmd)
      $else
      set vi-cmd-mode-string [cmd]
      $endif
    LINES

    assert_equal '[cmd]', get_config_variable(:@vi_cmd_mode_string)
  end

  def test_if_with_indent
    %w[Ruby Reline].each do |cond|
      @config.read_lines(<<~LINES.lines)
        set vi-cmd-mode-string {cmd}
          $if #{cond}
            set vi-cmd-mode-string (cmd)
          $else
            set vi-cmd-mode-string [cmd]
          $endif
      LINES

      assert_equal '(cmd)', get_config_variable(:@vi_cmd_mode_string)
    end
  end

  def test_nested_if_else
    @config.read_lines(<<~LINES.lines)
      $if Ruby
        "\x1": "O"
        $if NotRuby
          "\x2": "X"
        $else
          "\x3": "O"
          $if Ruby
            "\x4": "O"
          $else
            "\x5": "X"
          $endif
          "\x6": "O"
        $endif
        "\x7": "O"
      $else
        "\x8": "X"
        $if NotRuby
          "\x9": "X"
        $else
          "\xA": "X"
        $endif
        "\xB": "X"
      $endif
      "\xC": "O"
    LINES
    keys = [0x1, 0x3, 0x4, 0x6, 0x7, 0xC]
    key_bindings = keys.to_h { |k| [[k], ['O'.ord]] }
    assert_equal(key_bindings, additional_key_bindings(:emacs))
  end

  def test_unclosed_if
    e = assert_raise(Reline::Config::InvalidInputrc) do
      @config.read_lines(<<~LINES.lines, "INPUTRC")
        $if Ruby
      LINES
    end
    assert_equal "INPUTRC:1: unclosed if", e.message
  end

  def test_unmatched_else
    e = assert_raise(Reline::Config::InvalidInputrc) do
      @config.read_lines(<<~LINES.lines, "INPUTRC")
        $else
      LINES
    end
    assert_equal "INPUTRC:1: unmatched else", e.message
  end

  def test_unmatched_endif
    e = assert_raise(Reline::Config::InvalidInputrc) do
      @config.read_lines(<<~LINES.lines, "INPUTRC")
        $endif
      LINES
    end
    assert_equal "INPUTRC:1: unmatched endif", e.message
  end

  def test_if_with_mode
    @config.read_lines(<<~LINES.lines)
      $if mode=emacs
        "\C-e": history-search-backward # comment
      $else
        "\C-f": history-search-forward
      $endif
    LINES

    assert_equal({[5] => :history_search_backward}, additional_key_bindings(:emacs))
    assert_equal({}, additional_key_bindings(:vi_insert))
    assert_equal({}, additional_key_bindings(:vi_command))
  end

  def test_else
    @config.read_lines(<<~LINES.lines)
      $if mode=vi
        "\C-e": history-search-backward # comment
      $else
        "\C-f": history-search-forward
      $endif
    LINES

    assert_equal({[6] => :history_search_forward}, additional_key_bindings(:emacs))
    assert_equal({}, additional_key_bindings(:vi_insert))
    assert_equal({}, additional_key_bindings(:vi_command))
  end

  def test_if_with_invalid_mode
    @config.read_lines(<<~LINES.lines)
      $if mode=vim
        "\C-e": history-search-backward
      $else
        "\C-f": history-search-forward # comment
      $endif
    LINES

    assert_equal({[6] => :history_search_forward}, additional_key_bindings(:emacs))
    assert_equal({}, additional_key_bindings(:vi_insert))
    assert_equal({}, additional_key_bindings(:vi_command))
  end

  def test_mode_label_differs_from_keymap_label
    @config.read_lines(<<~LINES.lines)
      # Sets mode_label and keymap_label to vi
      set editing-mode vi
      # Change keymap_label to emacs. mode_label is still vi.
      set keymap emacs
      # condition=true because current mode_label is vi
      $if mode=vi
        # sets keybinding to current keymap_label=emacs
        "\C-e": history-search-backward
      $endif
    LINES
    assert_equal({[5] => :history_search_backward}, additional_key_bindings(:emacs))
    assert_equal({}, additional_key_bindings(:vi_insert))
    assert_equal({}, additional_key_bindings(:vi_command))
  end

  def test_if_without_else_condition
    @config.read_lines(<<~LINES.lines)
      set editing-mode vi
      $if mode=vi
        "\C-e": history-search-backward
      $endif
    LINES

    assert_equal({}, additional_key_bindings(:emacs))
    assert_equal({[5] => :history_search_backward}, additional_key_bindings(:vi_insert))
    assert_equal({}, additional_key_bindings(:vi_command))
  end

  def test_default_key_bindings
    @config.add_default_key_binding('abcd'.bytes, 'EFGH'.bytes)
    @config.read_lines(<<~'LINES'.lines)
      "abcd": "ABCD"
      "ijkl": "IJKL"
    LINES

    expected = { 'abcd'.bytes => 'ABCD'.bytes, 'ijkl'.bytes => 'IJKL'.bytes }
    assert_equal expected, registered_key_bindings(expected.keys)
  end

  def test_additional_key_bindings
    @config.read_lines(<<~'LINES'.lines)
      "ef": "EF"
      "gh": "GH"
    LINES

    expected = { 'ef'.bytes => 'EF'.bytes, 'gh'.bytes => 'GH'.bytes }
    assert_equal expected, registered_key_bindings(expected.keys)
  end

  def test_unquoted_additional_key_bindings
    @config.read_lines(<<~'LINES'.lines)
      Meta-a: "Ma"
      Control-b: "Cb"
      Meta-Control-c: "MCc"
      Control-Meta-d: "CMd"
      M-C-e: "MCe"
      C-M-f: "CMf"
    LINES

    expected = { "\ea".bytes => 'Ma'.bytes, "\C-b".bytes => 'Cb'.bytes, "\e\C-c".bytes => 'MCc'.bytes, "\e\C-d".bytes => 'CMd'.bytes, "\e\C-e".bytes => 'MCe'.bytes, "\e\C-f".bytes => 'CMf'.bytes }
    assert_equal expected, registered_key_bindings(expected.keys)
  end

  def test_additional_key_bindings_with_nesting_and_comment_out
    @config.read_lines(<<~'LINES'.lines)
      #"ab": "AB"
        #"cd": "cd"
      "ef": "EF"
        "gh": "GH"
    LINES

    expected = { 'ef'.bytes => 'EF'.bytes, 'gh'.bytes => 'GH'.bytes }
    assert_equal expected, registered_key_bindings(expected.keys)
  end

  def test_additional_key_bindings_for_other_keymap
    @config.read_lines(<<~'LINES'.lines)
      set keymap vi-command
      "ab": "AB"
      set keymap vi-insert
      "cd": "CD"
      set keymap emacs
      "ef": "EF"
      set editing-mode vi # keymap changes to be vi-insert
    LINES

    expected = { 'cd'.bytes => 'CD'.bytes }
    assert_equal expected, registered_key_bindings(expected.keys)
  end

  def test_additional_key_bindings_for_auxiliary_emacs_keymaps
    @config.read_lines(<<~'LINES'.lines)
      set keymap emacs
      "ab": "AB"
      set keymap emacs-standard
      "cd": "CD"
      set keymap emacs-ctlx
      "ef": "EF"
      set keymap emacs-meta
      "gh": "GH"
      set editing-mode emacs # keymap changes to be emacs
    LINES

    expected = {
      'ab'.bytes => 'AB'.bytes,
      'cd'.bytes => 'CD'.bytes,
      "\C-xef".bytes => 'EF'.bytes,
      "\egh".bytes => 'GH'.bytes,
    }
    assert_equal expected, registered_key_bindings(expected.keys)
  end

  def test_key_bindings_with_reset
    # @config.reset is called after each readline.
    # inputrc file is read once, so key binding shouldn't be cleared by @config.reset
    @config.add_default_key_binding('default'.bytes, 'DEFAULT'.bytes)
    @config.read_lines(<<~'LINES'.lines)
      "additional": "ADDITIONAL"
    LINES
    @config.reset
    expected = { 'default'.bytes => 'DEFAULT'.bytes, 'additional'.bytes => 'ADDITIONAL'.bytes }
    assert_equal expected, registered_key_bindings(expected.keys)
  end

  def test_history_size
    @config.read_lines(<<~LINES.lines)
      set history-size 5000
    LINES

    assert_equal 5000, get_config_variable(:@history_size)
    history = Reline::History.new(@config)
    history << "a\n"
    assert_equal 1, history.size
  end

  def test_empty_inputrc_env
    inputrc_backup = ENV['INPUTRC']
    ENV['INPUTRC'] = ''
    assert_nothing_raised do
      @config.read
    end
  ensure
    ENV['INPUTRC'] = inputrc_backup
  end

  def test_inputrc
    inputrc_backup = ENV['INPUTRC']
    expected = "#{@tmpdir}/abcde"
    ENV['INPUTRC'] = expected
    assert_equal expected, @config.inputrc_path
  ensure
    ENV['INPUTRC'] = inputrc_backup
  end

  def test_inputrc_raw_value
    @config.read_lines(<<~'LINES'.lines)
      set editing-mode vi ignored-string
      set vi-ins-mode-string aaa aaa
      set vi-cmd-mode-string bbb ccc # comment
    LINES
    assert_equal :vi_insert, get_config_variable(:@editing_mode_label)
    assert_equal 'aaa aaa', @config.vi_ins_mode_string
    assert_equal 'bbb ccc # comment', @config.vi_cmd_mode_string
  end

  def test_inputrc_with_utf8
    # This file is encoded by UTF-8 so this heredoc string is also UTF-8.
    @config.read_lines(<<~'LINES'.lines)
      set editing-mode vi
      set vi-cmd-mode-string 🍸
      set vi-ins-mode-string 🍶
    LINES
    assert_equal '🍸', @config.vi_cmd_mode_string
    assert_equal '🍶', @config.vi_ins_mode_string
  rescue Reline::ConfigEncodingConversionError
    # do nothing
  end

  def test_inputrc_with_eucjp
    @config.read_lines(<<~"LINES".encode(Encoding::EUC_JP).lines)
      set editing-mode vi
      set vi-cmd-mode-string ｫｬｯ
      set vi-ins-mode-string 能
    LINES
    assert_equal 'ｫｬｯ'.encode(Reline.encoding_system_needs), @config.vi_cmd_mode_string
    assert_equal '能'.encode(Reline.encoding_system_needs), @config.vi_ins_mode_string
  rescue Reline::ConfigEncodingConversionError
    # do nothing
  end

  def test_empty_inputrc
    assert_nothing_raised do
      @config.read_lines([])
    end
  end

  def test_xdg_config_home
    home_backup = ENV['HOME']
    xdg_config_home_backup = ENV['XDG_CONFIG_HOME']
    inputrc_backup = ENV['INPUTRC']
    xdg_config_home = File.expand_path("#{@tmpdir}/.config/example_dir")
    expected = File.expand_path("#{xdg_config_home}/readline/inputrc")
    FileUtils.mkdir_p(File.dirname(expected))
    FileUtils.touch(expected)
    ENV['HOME'] = @tmpdir
    ENV['XDG_CONFIG_HOME'] = xdg_config_home
    ENV['INPUTRC'] = ''
    assert_equal expected, @config.inputrc_path
  ensure
    FileUtils.rm(expected)
    ENV['XDG_CONFIG_HOME'] = xdg_config_home_backup
    ENV['HOME'] = home_backup
    ENV['INPUTRC'] = inputrc_backup
  end

  def test_empty_xdg_config_home
    home_backup = ENV['HOME']
    xdg_config_home_backup = ENV['XDG_CONFIG_HOME']
    inputrc_backup = ENV['INPUTRC']
    ENV['HOME'] = @tmpdir
    ENV['XDG_CONFIG_HOME'] = ''
    ENV['INPUTRC'] = ''
    expected = File.expand_path('~/.config/readline/inputrc')
    FileUtils.mkdir_p(File.dirname(expected))
    FileUtils.touch(expected)
    assert_equal expected, @config.inputrc_path
  ensure
    FileUtils.rm(expected)
    ENV['XDG_CONFIG_HOME'] = xdg_config_home_backup
    ENV['HOME'] = home_backup
    ENV['INPUTRC'] = inputrc_backup
  end

  def test_relative_xdg_config_home
    home_backup = ENV['HOME']
    xdg_config_home_backup = ENV['XDG_CONFIG_HOME']
    inputrc_backup = ENV['INPUTRC']
    ENV['HOME'] = @tmpdir
    ENV['INPUTRC'] = ''
    expected = File.expand_path('~/.config/readline/inputrc')
    FileUtils.mkdir_p(File.dirname(expected))
    FileUtils.touch(expected)
    result = Dir.chdir(@tmpdir) do
      xdg_config_home = ".config/example_dir"
      ENV['XDG_CONFIG_HOME'] = xdg_config_home
      inputrc = "#{xdg_config_home}/readline/inputrc"
      FileUtils.mkdir_p(File.dirname(inputrc))
      FileUtils.touch(inputrc)
      @config.inputrc_path
    end
    assert_equal expected, result
    FileUtils.rm(expected)
    ENV['XDG_CONFIG_HOME'] = xdg_config_home_backup
    ENV['HOME'] = home_backup
    ENV['INPUTRC'] = inputrc_backup
  end

  def test_reload
    inputrc = "#{@tmpdir}/inputrc"
    ENV['INPUTRC'] = inputrc

    File.write(inputrc, "set emacs-mode-string !")
    @config.read
    assert_equal '!', @config.emacs_mode_string

    File.write(inputrc, "set emacs-mode-string ?")
    @config.reload
    assert_equal '?', @config.emacs_mode_string

    File.write(inputrc, "")
    @config.reload
    assert_equal '@', @config.emacs_mode_string
  end

  def test_invalid_byte_sequence_inputrc
    lines = [
      "set vi-cmd-mode-string\n",
      "$if Ruby\n",
      "  \"\C-a\": \"Ruby\"\n",
      "$else \"\xFF\"\n".dup.force_encoding(Reline.encoding_system_needs), # Invalid byte sequence
      "  \"\C-b\": \"NotRuby\"\n",
      "$endif\n"
    ]

    e = assert_raise(Reline::Config::InvalidInputrc) do
      @config.read_lines(lines, "INPUTRC")
    end

    assert_equal "INPUTRC:4: can't be converted to the locale #{Reline.encoding_system_needs}", e.message
  end
end
