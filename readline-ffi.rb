require 'ffi'

module ReadlineFFI
  extend FFI::Library
  ffi_lib 'readline'
  callback :rl_vcpfunc_t, [:string], :void # void returning char* function
  attach_function :readline, [:string], :string
  attach_function :rl_callback_handler_install, [:string, :rl_vcpfunc_t], :void
  attach_function :rl_callback_handler_remove, [], :void
  attach_function :rl_callback_read_char, [], :void
  attach_function :rl_forced_update_display, [], :int
  attach_function :rl_clear_visible_line, [], :int
  attach_function :rl_set_prompt, [:string], :int
  attach_function :rl_prep_terminal, [], :void
  attach_function :rl_deprep_terminal, [], :void
  attach_function :add_history, [:string], :void
  attach_function :write_history, [:string], :int
  attach_function :read_history, [:string], :int

  module CFFI
    extend FFI::Library
    ffi_lib 'c'
    attach_function :fflush, [:pointer], :int
    attach_function :strerror, [:int], :string
  end
end
