# frozen_string_literal: true

module Chip8
  ##
  # Virtual machine
  class VM
    MEMORY_SIZE = 4096
    REGISTERS_NUM = 16
    STACK_SIZE = 16
    START_ADDRESS = 0x200
    DISPLAY_WIDTH = 64
    DISPLAY_HEIGHT = 32
    DISPLAY_SIZE = DISPLAY_WIDTH * DISPLAY_HEIGHT
    FONT_OFFSET = 0
    FONT_WIDTH = 8
    FONT_HEIGHT = 5
    KEYS_NUM = 16

    OPCODES = {
      [0x0, nil, nil, nil] => nil,                        # 0nnn SYS addr
      [0x0, 0x0, 0xe, 0x0] => :clear_display,             # 00E0 CLS
      [0x0, 0x0, 0xe, 0xe] => :return_sub,                # 00EE RET
      [0x1, nil, nil, nil] => :jump_location,             # 1nnn JP addr
      [0x2, nil, nil, nil] => :call_sub,                  # 2nnn CALL addr
      [0x3, nil, nil, nil] => :skip_equal_byte,           # 3xkk SE Vx, byte
      [0x4, nil, nil, nil] => :skip_not_equal_byte,       # 4xkk SNE Vx, byte
      [0x5, nil, nil, 0x0] => :skip_equal_registers,      # 5xy0 SE Vx, Vy
      [0x6, nil, nil, nil] => :load_register_byte,        # 6xkk LD Vx, byte
      [0x7, nil, nil, nil] => :add_register_byte,         # 7xkk ADD Vx, byte
      [0x8, nil, nil, 0x0] => :load_register_register,    # 8xy0 LD Vx, Vy
      [0x8, nil, nil, 0x1] => :or_register_register,      # 8xy1 OR Vx, Vy
      [0x8, nil, nil, 0x2] => :and_register_register,     # 8xy2 AND Vx, Vy
      [0x8, nil, nil, 0x3] => :xor_register_register,     # 8xy3 XOR Vx, Vy
      [0x8, nil, nil, 0x4] => :add_register_carry,        # 8xy4 ADC Vx, Vy
      [0x8, nil, nil, 0x5] => :sub_register_borrow,       # 8xy5 SUB Vx, Vy
      [0x8, nil, nil, 0x6] => :shr_register,              # 8xy6 SHR Vx {, Vy}
      [0x8, nil, nil, 0x7] => :subn_register_borrow,      # 8xy7 SUBN Vx, Vy
      [0x8, nil, nil, 0xe] => :shl_register,              # 8xyE SHL Vx {, Vy}
      [0x9, nil, nil, 0x0] => :skip_not_equal_registers,  # 9xy0 SNE Vx, Vy
      [0xa, nil, nil, nil] => :load_index_register,       # Annn LD I, addr
      [0xb, nil, nil, nil] => :jump_location_register,    # Bnnn JP V0, addr
      [0xc, nil, nil, nil] => :random_number,             # Cxkk RND Vx, byte
      [0xd, nil, nil, nil] => :draw_sprite,               # Dxyn DRW Vx, Vy
      [0xe, nil, 0x9, 0xe] => :skip_key_pressed,          # Ex9E SKP Vx
      [0xe, nil, 0xa, 0x1] => :skip_key_not_pressed,      # ExA1 SKNP Vx
      [0xf, nil, 0x0, 0x7] => :load_register_dt,          # Fx07 LD Vx, DT
      [0xf, nil, 0x0, 0xa] => :load_register_key,         # Fx0A LD Vx, K
      [0xf, nil, 0x1, 0x5] => :load_dt_register,          # Fx15 LD DT, Vx
      [0xf, nil, 0x1, 0x8] => :load_st_register,          # Fx18 LD ST, Vx
      [0xf, nil, 0x1, 0xe] => :add_index_register,        # Fx1E ADD I, Vx
      [0xf, nil, 0x2, 0x9] => :load_index_font,           # Fx29 LD F, Vx
      [0xf, nil, 0x3, 0x3] => :load_bcd_register,         # Fx33 LD B, Vx
      [0xf, nil, 0x5, 0x5] => :load_index_registers,      # Fx55 LD [I], Vx
      [0xf, nil, 0x6, 0x5] => :load_registers_index       # Fx65 LD Vx, [I]
    }.freeze

    FONT = [
      0xf0, 0x90, 0x90, 0x90, 0xf0, # 0
      0x20, 0x60, 0x20, 0x20, 0x70, # 1
      0xf0, 0x10, 0xf0, 0x80, 0xf0, # 2
      0xf0, 0x10, 0xf0, 0x10, 0xf0, # 3
      0x90, 0x90, 0xf0, 0x10, 0x10, # 4
      0xf0, 0x80, 0xf0, 0x10, 0xf0, # 5
      0xf0, 0x80, 0xf0, 0x90, 0xf0, # 6
      0xf0, 0x10, 0x20, 0x40, 0x40, # 7
      0xf0, 0x90, 0xf0, 0x90, 0xf0, # 8
      0xf0, 0x90, 0xf0, 0x10, 0xf0, # 9
      0xf0, 0x90, 0xf0, 0x90, 0x90, # A
      0xe0, 0x90, 0xe0, 0x90, 0xe0, # B
      0xf0, 0x80, 0x80, 0x80, 0xf0, # C
      0xe0, 0x90, 0x90, 0x90, 0xe0, # D
      0xf0, 0x80, 0xf0, 0x80, 0xf0, # E
      0xf0, 0x80, 0xf0, 0x80, 0x80  # F
    ].freeze

    attr_reader :rv, :ri, :sp, :pc, :dt, :st, :display, :memory, :stack

    attr_accessor :keys

    def initialize
      reset
    end

    def reset
      @rv = Array.new(REGISTERS_NUM, 0)
      @ri = 0
      @memory = Array.new(MEMORY_SIZE, 0)
      @display = Array.new(DISPLAY_SIZE, 0)
      @stack = Array.new(STACK_SIZE, 0)
      @sp = STACK_SIZE - 1
      @pc = START_ADDRESS
      @opcode = Array.new(4, 0)
      @keys = Array.new(KEYS_NUM, false)
      @dt = 0
      @st = 0

      load_font
    end

    def load_memory(data, address = START_ADDRESS)
      raise LoadError, 'Loading data is too large' if address + data.length > MEMORY_SIZE

      data.each_byte.with_index do |byte, i|
        @memory[address + i] = byte
      end
    end

    def run
      @running = true
      while @running
        step
        yield if block_given?
      end
    end

    def stop
      @running = false
    end

    def step
      opcode = (@memory[@pc] << 8) + @memory[@pc + 1]
      @opcode[0] = (opcode >> 12) & 0xf
      @opcode[1] = (opcode >> 8) & 0xf
      @opcode[2] = (opcode >> 4) & 0xf
      @opcode[3] = opcode & 0xf

      opcodes = OPCODES
      [0, 3, 2, 1].each do |i|
        opcodes = opcodes.select { |k| k[i] == @opcode[i] }
        break if opcodes.length <= 1
      end

      raise VMError, "Illegal opcode #{opcode.to_s(16)}" if opcodes.nil? || opcodes.empty?

      send(opcodes.values.first)
    end

    private

    def load_font
      FONT.each_with_index do |byte, i|
        @memory[FONT_OFFSET + i] = byte
      end
    end

    def next_opcode(n = 2)
      @pc = (@pc + n) & (MEMORY_SIZE - 1)
    end

    def clear_display
      @display.map! { 0 }
      next_opcode
    end

    def jump_location
      @pc = (@opcode[1] << 8) + (@opcode[2] << 4) + @opcode[3]
    end

    def return_sub
      @pc = @stack[@sp + 1]
      @sp = (@sp + 1) & (STACK_SIZE - 1)
      next_opcode
    end

    def call_sub
      @stack[@sp] = @pc
      @pc = (@opcode[1] << 8) + (@opcode[2] << 4) + @opcode[3]
      @sp = (@sp - 1) & (STACK_SIZE - 1)
    end

    def skip_equal_byte
      n = 2
      n += 2 if @rv[@opcode[1]] == (@opcode[2] << 4) + @opcode[3]
      next_opcode(n)
    end

    def skip_not_equal_byte
      n = 2
      n += 2 if @rv[@opcode[1]] != (@opcode[2] << 4) + @opcode[3]
      next_opcode(n)
    end

    def skip_equal_registers
      n = 2
      n += 2 if @rv[@opcode[1]] == @rv[@opcode[2]]
      next_opcode(n)
    end

    def load_register_byte
      @rv[@opcode[1]] = (@opcode[2] << 4) + @opcode[3]
      next_opcode
    end

    def add_register_byte
      byte = (@opcode[2] << 4) + @opcode[3]
      @rv[@opcode[1]] = (@rv[@opcode[1]] + byte) & 0xff
      next_opcode
    end

    def load_register_register
      @rv[@opcode[1]] = @rv[@opcode[2]]
      next_opcode
    end

    def or_register_register
      @rv[@opcode[1]] |= @rv[@opcode[2]]
      next_opcode
    end

    def and_register_register
      @rv[@opcode[1]] &= @rv[@opcode[2]]
      next_opcode
    end

    def xor_register_register
      @rv[@opcode[1]] ^= @rv[@opcode[2]]
      next_opcode
    end

    def add_register_carry
      sum = @rv[@opcode[1]] + @rv[@opcode[2]]
      @rv[0xf] = sum > 0xff ? 0x01 : 0x00
      @rv[@opcode[1]] = sum & 0xff
      next_opcode
    end

    def sub_register_borrow
      diff = @rv[@opcode[1]] - @rv[@opcode[2]]
      @rv[0xf] = diff >= 0 ? 0x01 : 0x00
      @rv[@opcode[1]] = diff & 0xff
      next_opcode
    end

    def shr_register
      @rv[0xf] = @rv[@opcode[1]] & 0x01
      @rv[@opcode[1]] >>= 1
      next_opcode
    end

    def subn_register_borrow
      diff = @rv[@opcode[2]] - @rv[@opcode[1]]
      @rv[0xf] = diff >= 0 ? 0x01 : 0x00
      @rv[@opcode[1]] = diff & 0xff
      next_opcode
    end

    def shl_register
      @rv[0xf] = (@rv[@opcode[1]] >> 7) & 0x01
      @rv[@opcode[1]] <<= 1
      next_opcode
    end

    def skip_not_equal_registers
      n = 2
      n += 2 if @rv[@opcode[1]] != @rv[@opcode[2]]
      next_opcode(n)
    end

    def load_index_register
      @ri = ((@opcode[1] << 8) + (@opcode[2] << 4) + @opcode[3]) & 0xfff
      next_opcode
    end

    def jump_location_register
      @pc = @rv[0x0] + ((@opcode[1] << 8) + (@opcode[2] << 4) + @opcode[3])
    end

    def random_number
      @rv[@opcode[1]] = Kernel.rand(0x100) & ((@opcode[2] << 4) + @opcode[3])
      next_opcode
    end

    def draw_sprite
      @rv[0xf] = 0
      @opcode[3].times do |i|
        FONT_WIDTH.times do |j|
          p = ((@rv[@opcode[2]] + i) * DISPLAY_WIDTH) + @rv[@opcode[1]] + j
          p %= DISPLAY_SIZE
          v = (@memory[@ri + i] >> (FONT_WIDTH - j - 1)) & 0x01
          @rv[0xf] |= @display[p] ^= v
        end
      end

      next_opcode
    end

    def skip_key_pressed
      n = 2
      if @keys[@rv[@opcode[1]]]
        n += 2
        @keys[@rv[@opcode[1]]] = false
      end

      next_opcode(n)
    end

    def skip_key_not_pressed
      n = 2
      n += 2 unless @keys[@rv[@opcode[1]]]
      next_opcode(n)
    end

    def load_register_dt
      @rv[@opcode[1]] = @dt
      next_opcode
    end

    def load_register_key
      return unless @keys.any?(true)

      @rv[@opcode[1]] = @keys.index(true)
      next_opcode
    end

    def load_dt_register
      @dt = @rv[@opcode[1]]
      next_opcode
    end

    def load_st_register
      @st = @rv[@opcode[1]]
      next_opcode
    end

    def add_index_register
      @ri = (@ri + @rv[@opcode[1]]) & 0xfff
      next_opcode
    end

    def load_index_font
      @ri = FONT_OFFSET + (FONT_HEIGHT * @rv[@opcode[1]])
      next_opcode
    end

    def load_bcd_register
      @memory[@ri] = @rv[@opcode[1]] / 100
      @memory[@ri + 1] = @rv[@opcode[1]] / 10 % 10
      @memory[@ri + 2] = @rv[@opcode[1]] % 10
      next_opcode
    end

    def load_index_registers
      (@opcode[1] + 1).times do |i|
        @memory[@ri + i] = @rv[i]
      end
      next_opcode
    end

    def load_registers_index
      (@opcode[1] + 1).times do |i|
        @rv[i] = @memory[@ri + i]
      end
      next_opcode
    end
  end

  ##
  # Virtual machine error
  class VMError < StandardError; end

  ##
  # Load error
  class LoadError < StandardError; end
end
