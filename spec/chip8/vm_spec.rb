# frozen_string_literal: true

require 'chip8'

RSpec.describe Chip8::VM do
  vm = described_class.new

  it 'Reset registers' do
    described_class::REGISTERS_NUM.times do |i|
      expect(vm.rv[i]).to eq(0)
    end

    expect(vm.ri).to eq(0)
  end

  it 'Reset memory' do
    expect(vm.memory[described_class::START_ADDRESS..].all?(0)).to be(true)
  end

  it 'Reset display' do
    expect(vm.display.all?(0)).to be(true)
  end

  it 'Reset stack' do
    expect(vm.stack.all?(0)).to be(true)
  end

  it 'Reset stack pointer' do
    expect(vm.sp).to eq(described_class::STACK_SIZE - 1)
  end

  it 'Reset program counter' do
    expect(vm.pc).to eq(described_class::START_ADDRESS)
  end

  it 'Reset delay timer' do
    expect(vm.dt).to eq(0)
  end

  it 'Reset sound timer' do
    expect(vm.st).to eq(0)
  end

  it 'Load memory' do
    data = "\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f"
    vm.load_memory(data)
    data.each_byte.with_index do |byte, i|
      expect(vm.memory[described_class::START_ADDRESS + i]).to eq(byte)
    end
    vm.reset

    data = "\xf0" * described_class::MEMORY_SIZE
    expect { vm.load_memory(data) }.to raise_error(Chip8::LoadError)
    vm.reset
  end

  it 'Clear display' do
    data = "\x00\xe0"
    vm.load_memory(data)
    vm.step
    expect(vm.display.all?(0)).to be(true)
    vm.reset
  end

  it 'Return subroutine' do
    data = "\x22\x06\x00\x00\x00\x00\x00\xee"
    vm.load_memory(data)
    vm.step
    expect(vm.pc).to eq(0x206)
    expect(vm.sp).to eq(described_class::STACK_SIZE - 2)
    vm.step
    expect(vm.sp).to eq(described_class::STACK_SIZE - 1)
    expect(vm.pc).to eq(0x202)
    vm.reset
  end

  it 'Jump location' do
    data = "\x15\xf3"
    vm.load_memory(data)
    vm.step
    expect(vm.pc).to eq(0x5f3)
    vm.reset
  end

  it 'Call subroutine' do
    data = "\x29\x05"
    vm.load_memory(data)
    vm.step
    expect(vm.pc).to eq(0x905)
    expect(vm.sp).to eq(described_class::STACK_SIZE - 2)
    expect(vm.stack[vm.sp + 1]).to eq(0x200)
    vm.reset
  end

  it 'Skip equal byte' do
    data = "\x30\xf5"

    vm.load_memory(data)
    vm.rv[0x0] = 0xf5
    vm.step
    expect(vm.pc).to eq(0x204)
    vm.reset

    vm.load_memory(data)
    vm.rv[0x0] = 0x39
    vm.step
    expect(vm.pc).to eq(0x202)
    vm.reset
  end

  it 'Skip not equal byte' do
    data = "\x41\x28"

    vm.load_memory(data)
    vm.rv[0x1] = 0x42
    vm.step
    expect(vm.pc).to eq(0x204)
    vm.reset

    vm.load_memory(data)
    vm.rv[0x1] = 0x28
    vm.step
    expect(vm.pc).to eq(0x202)
    vm.reset
  end

  it 'Skip equal registers' do
    data = "\x52\x30"

    vm.load_memory(data)
    vm.rv[0x2] = 0xbb
    vm.rv[0x3] = 0xbb
    vm.step
    expect(vm.pc).to eq(0x204)
    vm.reset

    vm.load_memory(data)
    vm.rv[0x2] = 0xbb
    vm.rv[0x3] = 0x90
    vm.step
    expect(vm.pc).to eq(0x202)
    vm.reset
  end

  it 'Load register byte' do
    data = "\x64\x1a"
    vm.load_memory(data)
    vm.step
    expect(vm.rv[0x4]).to eq(0x1a)
    vm.reset
  end

  it 'Add register byte' do
    data = "\x65\x45\x75\x02"
    vm.load_memory(data)
    2.times { vm.step }
    expect(vm.rv[0x5]).to eq(0x47)
    vm.reset
  end

  it 'Load register to register' do
    data = "\x66\xd0\x87\x60"
    vm.load_memory(data)
    2.times { vm.step }
    expect(vm.rv[0x6]).to eq(vm.rv[0x7])
    vm.reset
  end

  it 'Bitwise OR' do
    data = "\x68\x71\x69\x05\x88\x91"
    vm.load_memory(data)
    3.times { vm.step }
    expect(vm.rv[0x8]).to eq(0x75)
    vm.reset
  end

  it 'Bitwise AND' do
    data = "\x6a\xdf\x6b\x34\x8a\xb2"
    vm.load_memory(data)
    3.times { vm.step }
    expect(vm.rv[0xa]).to eq(0x14)
    vm.reset
  end

  it 'Bitwise XOR' do
    data = "\x6c\xc5\x6d\x51\x8c\xd3"
    vm.load_memory(data)
    3.times { vm.step }
    expect(vm.rv[0xc]).to eq(0x94)
    vm.reset
  end

  it 'Add register to register with carry' do
    data = "\x63\xfa\x64\x09\x83\x44"
    vm.load_memory(data)
    3.times { vm.step }
    expect(vm.rv[0x3]).to eq(0x03)
    expect(vm.rv[0xf]).to eq(0x01)
    vm.reset

    data = "\x63\x36\x64\x09\x83\x44"
    vm.load_memory(data)
    3.times { vm.step }
    expect(vm.rv[0x3]).to eq(0x3f)
    expect(vm.rv[0xf]).to eq(0x00)
    vm.reset
  end

  it 'Substract register to register with borrow' do
    data = "\x6a\x25\x6b\x05\x8a\xb5"
    vm.load_memory(data)
    3.times { vm.step }
    expect(vm.rv[0xa]).to eq(0x20)
    expect(vm.rv[0xf]).to eq(0x01)
    vm.reset

    data = "\x6a\x03\x6b\x05\x8a\xb5"
    vm.load_memory(data)
    3.times { vm.step }
    expect(vm.rv[0xa]).to eq(0xfe)
    expect(vm.rv[0xf]).to eq(0x00)
    vm.reset
  end

  it 'Bitwise shift right' do
    data = "\x6a\x64\x8a\x06"
    vm.load_memory(data)
    2.times { vm.step }
    expect(vm.rv[0xa]).to eq(0x32)
    vm.reset
  end

  it 'Substract2 register to register with borrow' do
    data = "\x6a\x02\x6b\x37\x8a\xb7"
    vm.load_memory(data)
    3.times { vm.step }
    expect(vm.rv[0xa]).to eq(0x35)
    expect(vm.rv[0xf]).to eq(0x01)
    vm.reset

    data = "\x6a\x0f\x6b\x08\x8a\xb7"
    vm.load_memory(data)
    3.times { vm.step }
    expect(vm.rv[0xa]).to eq(0xf9)
    expect(vm.rv[0xf]).to eq(0x00)
    vm.reset
  end

  it 'Bitwise shift left' do
    data = "\x6a\x15\x8a\x0e"
    vm.load_memory(data)
    2.times { vm.step }
    expect(vm.rv[0xa]).to eq(0x2a)
    vm.reset
  end

  it 'Skip not equal registers' do
    data = "\x60\x7d\x61\x95\x90\x10"
    vm.load_memory(data)
    3.times { vm.step }
    expect(vm.pc).to eq(0x208)
    vm.reset

    data = "\x60\x4f\x61\x4f\x90\x10"
    vm.load_memory(data)
    3.times { vm.step }
    expect(vm.pc).to eq(0x206)
    vm.reset
  end

  it 'Load index register' do
    data = "\xa3\xab"
    vm.load_memory(data)
    vm.step
    expect(vm.ri).to eq(0x3ab)
    vm.reset
  end

  it 'Jump location register' do
    data = "\x60\x21\xb4\x10"
    vm.load_memory(data)
    2.times { vm.step }
    expect(vm.pc).to eq(0x431)
    vm.reset
  end

  it 'Random number' do
    data = "\xc0\xff"
    numbers = [0xd9, 0x90, 0xbd, 0x19, 0x6d]
    Kernel.srand(0xfafa)
    numbers.each do |n|
      vm.load_memory(data)
      vm.step
      expect(vm.rv[0x0]).to eq(n)
      vm.reset
    end
  end

  it 'Draw sprite' do
    data = "\xa2\x04\xd0\x02\x21\x84"
    vm.load_memory(data)
    2.times { vm.step }
    expect(vm.display[0..7]).to eq([0, 0, 1, 0, 0, 0, 0, 1])
    expect(vm.display[64..71]).to eq([1, 0, 0, 0, 0, 1, 0, 0])
    vm.reset
  end

  it 'Skip key pressed' do
    data = "\x61\x05\xe1\x9e"

    vm.load_memory(data)
    2.times { vm.step }
    expect(vm.pc).to eq(0x204)
    vm.reset

    vm.load_memory(data)
    vm.keys[0x5] = true
    2.times { vm.step }
    expect(vm.pc).to eq(0x206)
    vm.reset
  end

  it 'Skip key not pressed' do
    data = "\x62\x0b\xe2\xa1"

    vm.load_memory(data)
    2.times { vm.step }
    expect(vm.pc).to eq(0x206)
    vm.reset

    vm.load_memory(data)
    vm.keys[0xb] = true
    2.times { vm.step }
    expect(vm.pc).to eq(0x204)
    vm.reset
  end

  it 'Load delay timer to register' do
    data = "\xf5\x07"
    vm.load_memory(data)
    vm.instance_variable_set(:@dt, 0xdc)
    vm.step
    expect(vm.rv[0x5]).to eq(0xdc)
    vm.reset
  end

  it 'Load key to register' do
    data = "\xfa\x0a"
    vm.load_memory(data)
    10.times { vm.step }
    expect(vm.pc).to eq(0x200)
    vm.keys[0x7] = true
    vm.step
    expect(vm.pc).to eq(0x202)
    expect(vm.rv[0xa]).to eq(0x07)
    vm.reset
  end

  it 'Load register to delay timer' do
    data = "\x62\x99\xf2\x15"
    vm.load_memory(data)
    2.times { vm.step }
    expect(vm.dt).to eq(0x99)
    vm.reset
  end

  it 'Load register to sound timer' do
    data = "\x64\xab\xf4\x18"
    vm.load_memory(data)
    2.times { vm.step }
    expect(vm.st).to eq(0xab)
    vm.reset
  end

  it 'Add index register' do
    data = "\xa4\x04\x6c\x05\xfc\x1e"
    vm.load_memory(data)
    3.times { vm.step }
    expect(vm.ri).to eq(0x409)
    vm.reset
  end

  it 'Load index font' do
    data = "\x6e\x04\xfe\x29"
    vm.load_memory(data)
    2.times { vm.step }
    expect(vm.ri).to eq(described_class::FONT_OFFSET + (0x4 * described_class::FONT_HEIGHT))
    vm.reset
  end

  it 'Load BCD register' do
    data = "\x65\x91\xa5\x00\xf5\x33"
    vm.load_memory(data)
    3.times { vm.step }
    expect(vm.ri).to eq(0x500)
    expect(vm.memory[vm.ri]).to eq(1)
    expect(vm.memory[vm.ri + 1]).to eq(4)
    expect(vm.memory[vm.ri + 2]).to eq(5)
    vm.reset
  end

  it 'Load index registers' do
    data = "\x60\x33\x61\xfa\x62\x42\xa6\x00\xf2\x55"
    vm.load_memory(data)
    5.times { vm.step }
    expect(vm.memory[vm.ri]).to eq(0x33)
    expect(vm.memory[vm.ri + 1]).to eq(0xfa)
    expect(vm.memory[vm.ri + 2]).to eq(0x42)
    vm.reset
  end

  it 'Load registers index' do
    numbers = [0x92, 0xde, 0x7f, 0xca, 0x27]
    data = "\xa6\x00\xf4\x65"
    vm.load_memory(data)
    numbers.each_with_index do |n, i|
      vm.memory[0x600 + i] = n
    end
    2.times { vm.step }
    numbers.each_with_index do |n, i|
      expect(vm.rv[i]).to eq(n)
    end
    vm.reset
  end
end
