#!/usr/bin/ruby

require "readline"

class C8vm
  MEMORY_SIZE = 0xfff
  ENTRY_ADDRESS = 0x200
  DISPLAY_WIDTH = 64
  DISPLAY_HEIGHT = 32
  PIXEL_FILL = "\e[47m \e[0m"
  PIXEL_BLANK = "\e[44m \e[0m"
  FREQUENCY = 60
  @started = false
  @running = false

  attr_reader :pc, :regv, :regi, :sp, :memory
  
  def initialize(file)
    reset
    @memory = Array.new(MEMORY_SIZE, 0)
    File.open(file, "r") do |rom|
      break unless rom
      i = ENTRY_ADDRESS
      rom.each_byte do |byte|
        break if i > MEMORY_SIZE
        @memory[i] = byte
        i += 1
      end
    end
  end

  def reset
    @pc = 0
    @regv = Array.new(16, 0)
    @regi = 0
    @sp = 0
    @stack = Array.new(16, 0)
    
    @timers = {
      delay: 0, sound: 0, display: 0,
    }

    @timersLast = {
      delay: nil, sound: nil, display: nil,
    }

    @display = Array.new(DISPLAY_WIDTH * DISPLAY_HEIGHT)
    @pc = ENTRY_ADDRESS    
  end
  
  def start
    return nil if @started
    @started = @running = true
    initDisplay
    while @started do
      tick if @running
      render if @timers[:display] == 0
    end
  end

  def stop
    @started = false
  end
  
  def pause
    @running = !@running
  end

  def tick
    tickTime = Time.now
    @timers.each_key do |k|
      if @timers[k] > 0 and (!@timersLast[k] or (tickTime - @timersLast[k]) * 100 >= 1.0 / FREQUENCY)
        @timers[k] -= 1
        @timersLast[k] = tickTime
      end
    end

    opcode = @memory[@pc, 2]
    opcode = opcode.pack("C*").unpack("n*").first
    o = [
      (opcode & 0xf000) >> 12,
      (opcode & 0x0f00) >> 8,
      (opcode & 0x00f0) >> 4,
      opcode & 0x000f,
    ]
    
    # 0x00e0 Clear screen
    if opcode == 0x00e0
      @display.each_index do |i|
        @display[i] = PIXEL_BLANK
      end
    # 0x00ee Return
    elsif opcode == 0x00ee
      @pc = @stack[@sp]
      @sp -= 1
      return
    # 0x1nnn Jump to address
    elsif o[0] == 0x1
      @pc = opcode & 0x0fff
      return
    # 0x2nnn Call subroutine
    elsif o[0] == 0x2
      @stack[@sp] = @pc
      @pc = opcode & 0x0fff
      @sp += 1
      return
    # 0x3xnn Skip if vx == nn
    elsif o[0] == 0x3
      if @regv[o[1]] == opcode & 0x00ff
        @pc += 4
        return
      end
    # 0x4xnn Skip if vx != nn
    elsif o[0] == 0x4
      if @regv[o[1]] != opcode & 0x0ff
        @pc += 4
        return
      end
    # 0x5xy0 Skip if vx == vy
    elsif o[0] == 0x5 and o[3] == 0x0
      if @regv[o[1]] == @regv[o[2]]
        @pc += 4
        return
      end
    # 0x6xnn Load nn to vx
    elsif o[0] == 0x6
      @regv[o[1]] = opcode & 0x00ff
    # 0x7xnn Load (vx + nn) to vx
    elsif o[0] == 0x7
     @regv[o[1]] += opcode & 0x00ff
      if @regv[o[1]] > 0xff
        @regv[o[1]] &= 0xff
        @regv[0xf] = 0x01
      else
        @regv[0xf] = 0x00
      end
    # 0x8xy0 Load vy to vx
    elsif o[0] == 0x8 and o[3] == 0x0
      @regv[o[1]] = @regv[o[2]]
    # 0x8xy1 Load (vx | vy) to vx
    elsif o[0] == 0x8 and o[3] == 0x1
      @regv[o[1]] |= @regv[o[2]]
    # 0x8xy2 Load (vx & vy) to vx
    elsif o[0] == 0x8 and o[3] == 0x2
      @regv[o[1]] &= @regv[o[2]]
    # 0x8xy3 Load (vx ^ vy) to vx
    elsif o[0] == 0x8 and o[3] == 0x3
      @regv[o[1]] ^= @regv[o[2]]
    # 0x8xy4 Load (vx + vy) to vx
    elsif o[0] == 0x8 and o[3] == 0x4
      @regv[o[1]] += @regv[o[2]]
      if @regv[o[1]] > 0xff
        @regv[o[1]] &= 0xff
        @regv[0xf] = 0x01
      else
        @regv[0xf] = 0x00
      end
    # 0x8xy5 Load (vx - vy) to vx
    elsif o[0] == 0x8 and o[3] == 0x5
      @regv[o[1]] -= @regv[o[2]]
      if @regv[o[1]] >= @regv[o[2]]
        @regv[0xf] = 0x1
      else
        @regv[0xf] = 0x0
      end
    # 0x8xy6 Load (vx >> 1) to vx
    elsif o[0] == 0x8 and o[3] == 0x6
      @regv[o[1]] = @regv[o[1]] >> 1
      if @regv[o[1]] & 0x1 == 0x1
        @regv[0xf] = 0x1
      else
        @regv[0xf] = 0x0
      end
    # 0x8xy7 if vy >= vx load (vy - vx) to vx  
    elsif o[0] == 0x8 and o[3] == 0x7
      if o[1] >= o[2]
        @regv[0xf] = 0x1
        @regv[o[1]] = @regv[o[2]] - @regv[o[1]]
      else
        @regv[0xf] = 0x0
      end
    # 0x8xye Load (vx << 1) to vx
    elsif o[0] == 0x8 and o[3] == 0xe
      @regv[o[1]] = @regv[o[1]] << 1
      if @regv[o[1]] & 0x1 == 0x1
        @regv[0xf] = 0x1
      else
        @regv[0xf] = 0x0
      end
    # 0x9xy0 Skip if vx != vy
    elsif o[0] == 0x9 and o[3] == 0
      if @regv[o[1]] != @regv[o[2]]
        @pc += 4
        return
      end
    # 0xannn Load nnn to i
    elsif o[0] == 0xa
      @regi = opcode & 0x0fff
    # 0xbnnn Jump to nnn + v0
    elsif o[0] == 0xb
      @pc = opcode & 0x0fff + @regv[0x0]
    # 0xcxnn Load random to vx
    elsif o[0] == 0xc
      @regv[o[1]] = rand(0..255) & (opcode & 0x00ff)
    # 0xdxyn Draw sprite
    elsif o[0] == 0xd
      o[3].times do |i|
        byte = @memory[@regi + i]
        8.times do |j|
          pixel = (@regv[o[2]] + i) * DISPLAY_WIDTH + @regv[o[1]] + j
          @display[pixel] = (byte >> (7 - j)) & 0x1 == 0x1 ? PIXEL_FILL : PIXEL_BLANK
        end
      end
    end

    @pc += 2
  end

  def initDisplay
    print "\e[2J"
  end

  def render
    print "\e[H"
    # return if @display == @displayPrev
    DISPLAY_HEIGHT.times do |y|
      DISPLAY_WIDTH.times do |x|
        print @display[y * DISPLAY_WIDTH + x]
      end
      print "\n"
    end

    @timers[:display] = FREQUENCY
    @displayPrev = @display.clone
  end
end

if ARGV[0]
  vm = nil
  while true
    cmd = Readline.readline("CHIP-8> ", true)
    next unless cmd
    cmd.strip!
    cmd.downcase!
    next if cmd.empty?
    cmd = cmd.split(/\s+/)
    
    case cmd[0]
        
    when /^q(uit)?$/
      exit

    when /^l(oad)?$/
      unless vm
        vm = C8vm.new(ARGV[0])
        puts "VM loaded"
      else
        puts "VM already loaded"
      end

    when /^i(nit)?$/
      if vm
        vm.reset
        puts "VM reseted"
      else
        puts "VM not loaded"
      end
      
    when /^r(un)?$/
      if vm
        vm.start
      else
        puts "VM not loaded"
      end

    when /^s(tep)?$/
      if vm
        puts "Step [PC %02x]" % vm.pc
        vm.tick
      else
        puts "VM not loaded"
      end
      
    when /^d(ump)?$/
      if vm
        puts "PC: %03x SP: %02x I: %03x" % [vm.pc, vm.sp, vm.regi]
        puts
        vm.regv.each_index do |i|
          print "V%01X: %02x" % [i, vm.regv[i]]
          print ((i + 1) % 8 == 0 and i != 0) ? "\n" : " "
        end
        puts
        a = cmd[1] ? cmd[1].to_i(16) : C8vm::ENTRY_ADDRESS
        if a >= 0 and a <= C8vm::MEMORY_SIZE
          16.times do |i|
            print "%03x | " % [a + (i * 0xf)]
            16.times do |j|
              print "%02x " % vm.memory[a + (i * 0xf) + j]
              print " " if j == 0x7
              puts if j == 0xf
            end
            a += 1
          end
        else
          puts "Invalid address"
        end
      else
        puts "VM not loaded"
      end
      
    end
      end
else
  puts "Usage: #{__FILE__} <rom>"
  exit
end
