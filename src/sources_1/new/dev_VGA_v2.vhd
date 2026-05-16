library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;

library UNISIM;
use UNISIM.vcomponents.all;

--  VGA
entity dev_VGA_v2 is
    generic (
        --  bus topology
        bus_width: integer := 32;
        data_width: integer := 8;
        addr_width: integer := 23;
        --  device manager setup
        dev_id: integer := 3;
        dev_mem_begin: integer := 0;    --  start of memory space for the UART device
        dev_mem_end: integer := 0;      --  end of memory space for the UART device
        --  character rom
        char_rom: string := "charmap.mem";
        clock_factor: natural := 4      --  vga clock at 25 MHz
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  system bus interface signals
        bus_lines: inout std_logic_vector(bus_width-1 downto 0);
        bus_strobe_M: inout std_logic;
        bus_strobe_S: inout std_logic;
        bus_keep: inout std_logic;
        bus_done_S: inout std_logic;
        bus_rq: out std_logic;
        bus_grant: in std_logic;
        bus_busy: in std_logic;
        --  hardware lines
        vga_R: out std_logic_vector(3 downto 0);
        vga_G: out std_logic_vector(3 downto 0);
        vga_B: out std_logic_vector(3 downto 0);
        vga_HS: out std_logic;
        vga_VS: out std_logic
    );
end dev_VGA_v2;

architecture Behavioral of dev_VGA_v2 is
    --  control registers
    signal r_dev_in_cmd: std_logic := '0';
    signal r_dev_in_addr: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal r_dev_in_data: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal r_dev_in_keep: std_logic := '0';
    signal r_dev_in_latch: std_logic := '0';
    
    -- output signals from bus interface
    signal s_dev_out_cmd: std_logic;
    signal s_dev_out_addr: std_logic_vector(addr_width-1 downto 0);
    signal s_dev_out_data: std_logic_vector(data_width-1 downto 0);
    signal s_dev_out_drdy: std_logic;
    signal s_dev_out_done: std_logic;
    signal s_dev_err: std_logic;
    signal s_dev_chg: std_logic;
    
    --  sampling signals
    signal ss_dev_out_cmd: std_logic;
    signal ss_dev_out_drdy: std_logic;
    signal ss_dev_out_done: std_logic;
    signal ss_dev_out_addr: std_logic_vector(addr_width-1 downto 0);
    signal ss_dev_out_data: std_logic_vector(data_width-1 downto 0);
    signal ss_dev_chg: std_logic;
    
    --  vga driving signals
    signal r_vga_R: std_logic_vector(3 downto 0) := (others=>'0');
    signal r_vga_G: std_logic_vector(3 downto 0) := (others=>'0');
    signal r_vga_B: std_logic_vector(3 downto 0) := (others=>'0');
    signal r_vga_HS: std_logic := '1';
    signal r_vga_VS: std_logic := '1';

    --  vga memory as 240 lines of 40 bytes each
    --  if instead I made: 30 chars over 160 lines? 4800 bytes invece di 9600, dimezzo. 
    --type vga_ram is array (0 to 239) of std_logic_vector(319 downto 0);
    type vga_ram is array (0 to 159) of std_logic_vector(239 downto 0);
    signal video_memory: vga_ram;
    signal video_memory_active: std_logic := '0';
    
    --  state machine
    type t_SM is (s_INIT, s_HSYNC, s_H_BP, s_H_FP, s_H_DISP, s_VSYNC, s_V_BP, s_V_DISP, s_V_FP);
    signal r_stage: t_SM := s_INIT;
    signal r_jump_0: t_SM := s_INIT;
    
    --  state machine for main
    type t_SM_main is (s_M_INIT, s_M_IDLE, s_M_REG, s_M_VRT_0, s_M_VRT_0_R, s_M_SYM_0, s_M_SYM_1, s_M_SYM_2, s_M_PX_0, s_M_CMD, s_M_CMD_0, s_M_CMD_1, s_M_CMD_2, s_M_CMD_3, s_M_CMD_8, s_M_CMD_9, s_M_CMD_10, s_M_CMD_11, s_M_CMD_12, s_M_CMD_13);
    signal r_m_stage: t_SM_main := s_M_INIT;
    signal r_m_jump: t_SM_main := s_M_INIT;
            
    --  character rom is a 2048 byte memory file that holds 256 symbols from Commodore-64-128
    --  reading the character rom
    type rom_type is array (0 to 2047) of std_logic_vector(7 downto 0);
    impure function init_rom_bin return rom_type is 
      file text_file : text open read_mode is char_rom;
      variable text_line : line;
      variable rom_content : rom_type;
      variable bv : bit_vector(rom_content(0)'range);
    begin
      for i in 0 to 2047 loop
        readline(text_file, text_line);
        read(text_line, bv);
        rom_content(i) := to_stdlogicvector(bv);
      end loop;
      return rom_content;
    end function;    
    --  and so finally
    signal character_rom: rom_type := init_rom_bin;
    
    --  useful constants for syncing
    constant npx_h_front_porch: natural := 16;
    constant npx_h_sync_pulse: natural := 96;
    constant npx_h_back_porch: natural := 48;
    constant nl_v_front_porch: natural := 10;
    constant nl_v_sync_pulse: natural := 2;
    constant nl_v_back_porch: natural := 33;
    
    --  useful constants for framing
    constant vis_h_begin: natural := 200; --160;
    constant vis_h_end: natural := 440; --480;
    constant vis_v_begin: natural := 160; --120;
    constant vis_v_end: natural := 320; --360;
    
    --  vga clk
    signal vgaClk: std_logic;
    
    --  registers to hold in the fore and background colors
    signal r_colors: std_logic_vector(23 downto 0);
     
begin
    --  vga drivers
    vga_R <= r_vga_R;
    vga_G <= r_vga_G;
    vga_B <= r_vga_B;
    vga_HS <= r_vga_HS;
    vga_VS <= r_vga_VS;
    
    BUFR_inst : BUFR
    generic map (
       BUFR_DIVIDE => "4",   -- Values: "BYPASS, 1, 2, 3, 4, 5, 6, 7, 8"
       SIM_DEVICE => "7SERIES"  -- Must be set to "7SERIES"
    )
    port map (
       O => vgaClk,     -- 1-bit output: Clock output port
       CE => '1',   -- 1-bit input: Active high, clock enable (Divided modes only)
       CLR => '0', -- 1-bit input: Active high, asynchronous clear (Divided modes only)
       I => sysClk      -- 1-bit input: Clock buffer input driven by an IBUF, MMCM or local interconnect
    );
          
    --  system bus interface
    BUS_DEV:    entity work.dev_v2(Behavioral)
                generic map (
                    dev_id => dev_id,
                    dev_mem_begin => dev_mem_begin,
                    dev_mem_end => dev_mem_end
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  interface signals
                    bus_lines => bus_lines,
                    bus_strobe_M => bus_strobe_M,
                    bus_strobe_S => bus_strobe_S,
                    bus_keep => bus_keep,
                    bus_done_S => bus_done_S,
                    bus_rq => bus_rq,
                    bus_grant => bus_grant,
                    bus_busy => bus_busy,
                    --  external interface signals
                    dev_in_cmd => r_dev_in_cmd,
                    dev_in_addr => r_dev_in_addr,
                    dev_in_data => r_dev_in_data,
                    dev_in_keep => r_dev_in_keep,
                    dev_in_latch => r_dev_in_latch,
                    dev_out_cmd => s_dev_out_cmd,
                    dev_out_addr => s_dev_out_addr,
                    dev_out_data => s_dev_out_data,
                    dev_out_drdy => s_dev_out_drdy,
                    dev_out_done => s_dev_out_done,
                    dev_err => s_dev_err,
                    dev_chg => s_dev_chg
                );
    
            
    --  this process generates the vga signals and displays the contents of the
    --  line buffer. This process is free running and the only thing it does is read
    --  from the line buffer and display each line on screen, sequentially.
    --  the contents of the line buffer are written elsewhere.
    --  the vga clock should be 25.175 MHz but is instead clocked at 25.173
    VGAGEN: process(vgaClk)
                --  pixel counter
                variable px_counter: natural := 0;
                variable l_counter: natural := 0;
                variable line_counter: natural := 0;
                variable vga_VS_i: std_logic := '1';
            begin
                if (rising_edge(vgaClk)) then
                    if (sysRstb='0') then
                        r_stage <= s_INIT;
                    else
                        case (r_stage) is
                            when s_INIT =>
                                --  initialization
                                px_counter := 0;
                                r_vga_R <= (others=>'0');
                                r_vga_G <= (others=>'0');
                                r_vga_B <= (others=>'0');
                                r_vga_HS <= '1';
                                r_vga_VS <= '1';
                                --  vmem active
                                video_memory_active <= '0';
                                --  counters
                                line_counter := 0;
                                --  going
                                r_stage <= s_VSYNC;
                            
                            --  LINE GENERATOR
                            --  let's start a line, so we start with a horizontal sync
                            when s_HSYNC =>
                                r_vga_HS <= '0';
                                r_vga_VS <= vga_VS_i;
                                video_memory_active <= '0';
                                if (px_counter=(npx_h_sync_pulse-1)) then
                                    px_counter := 0;
                                    r_stage <= s_H_BP;
                                else
                                    --  waiting                                    
                                    px_counter := px_counter + 1;
                                    r_stage <= s_HSYNC;
                                end if;
                            
                            when s_H_BP =>
                                r_vga_HS <= '1';
                                video_memory_active <= '0';
                                if (px_counter=(npx_h_back_porch-1)) then
                                    px_counter := 0;
                                    r_stage <= s_H_DISP;
                                else
                                    --  waiting
                                    px_counter := px_counter + 1;
                                    r_stage <= s_H_BP;
                                end if;
                            
                            when s_H_DISP =>
                                --  checking the zone
                                video_memory_active <= '1';
                                if ((px_counter >= vis_h_begin) and (px_counter < vis_h_end) and (line_counter >= vis_v_begin) and (line_counter < vis_v_end)) then
                                    --  active region is now 240x160 and not 320x240 since there is not enought memory
                                    if (video_memory(line_counter-vis_v_begin)(px_counter-vis_h_begin)='0') then
                                        --  zero is displayed as background color
                                        r_vga_R <= r_colors(23 downto 20);
                                        r_vga_G <= r_colors(19 downto 16);
                                        r_vga_B <= r_colors(15 downto 12);
                                    else
                                        --  one is displayed as foreground color
                                        r_vga_R <= r_colors(11 downto 8);
                                        r_vga_G <= r_colors(7 downto 4);
                                        r_vga_B <= r_colors(3 downto 0);
                                    end if;
                                else
                                    --  blank region
                                    r_vga_R <= "0000";
                                    r_vga_G <= "0000";
                                    r_vga_B <= "0000";
                                end if;
                                --  checking the location
                                if (px_counter=639) then
                                    --  end of the visible area
                                    px_counter := 0;
                                    r_stage <= s_H_FP; 
                                else
                                    --  staying here
                                    px_counter := px_counter + 1;
                                    r_stage <= s_H_DISP;
                                end if;
                            
                            when s_H_FP =>
                                video_memory_active <= '0';
                                if (px_counter=(npx_h_front_porch-2)) then
                                    px_counter := 0;
                                    r_stage <= r_jump_0;
                                else
                                    --  waiting
                                    px_counter := px_counter + 1;
                                    r_stage <= s_H_FP;
                                end if;
                                
                            --  FRAME GENERATOR
                            when s_VSYNC =>
                                video_memory_active <= '0';
                                if (l_counter=(nl_v_sync_pulse)) then
                                    --  done
                                    vga_VS_i := '1';
                                    l_counter := 0;
                                    r_jump_0 <= s_V_BP;
                                else
                                    --  waiting
                                    vga_VS_i := '0';
                                    r_jump_0 <= s_VSYNC;
                                    l_counter := l_counter + 1;
                                end if;
                                r_stage <= s_HSYNC;
                            
                            when s_V_BP =>
                                video_memory_active <= '0';
                                if (l_counter=(nl_v_back_porch-1)) then
                                    --  can now go in visual mode
                                    line_counter := 0;
                                    l_counter := 0;
                                    r_jump_0 <= s_V_DISP;
                                else
                                    --  waiting
                                    r_jump_0 <= s_V_BP;
                                    l_counter := l_counter + 1;
                                end if;
                                r_stage <= s_HSYNC;
                            
                            when s_V_DISP =>
                                video_memory_active <= '1';
                                if (line_counter=479) then
                                    --  showed all the lines, hence
                                    line_counter := 0;
                                    r_jump_0 <= s_V_FP;
                                else
                                    --  still have lines to show, so
                                    line_counter := line_counter + 1;
                                    r_jump_0 <= s_V_DISP;
                                end if;
                                r_stage <= s_HSYNC;
                            
                            when s_V_FP =>
                                video_memory_active <= '0';
                                if (l_counter=(nl_v_front_porch-1)) then
                                    --  done with the frame, can start again
                                    l_counter := 1;
                                    vga_VS_i := '0';
                                    r_jump_0 <= s_VSYNC;
                                else
                                    --  waiting
                                    l_counter := l_counter + 1;
                                    r_jump_0 <= s_V_FP;
                                end if;
                                r_stage <= s_HSYNC;
                        end case;
                    end if;
                end if;
            end process VGAGEN;

    SAMP:   process(sysClk)
            begin
                if (rising_edge(sysClk)) then
                    case (r_m_stage) is
                        when s_M_INIT =>
                            ss_dev_out_drdy <= '0';
                            ss_dev_chg <= '0';
                        
                        when s_M_IDLE =>
                            ss_dev_out_cmd <= s_dev_out_cmd;
                            ss_dev_out_drdy <= s_dev_out_drdy;
                            ss_dev_out_data <= s_dev_out_data;
                            ss_dev_out_addr <= s_dev_out_addr;
                            ss_dev_chg <= s_dev_chg;
                        
                        when s_M_REG =>
                            ss_dev_chg <= s_dev_chg;
                        
                        when s_M_SYM_2 =>
                            ss_dev_out_drdy <= s_dev_out_drdy;
                        
                        when others =>
                            null;
                        
                    end case;
                end if;
            end process SAMP;

    MAIN:   process(sysClk)
                variable cond: std_logic_vector(1 downto 0);
                variable addr: natural := 0;
                variable addr_binary: std_logic_vector(22 downto 0);
                variable row: natural := 0;
                variable col: natural := 0;
                variable symbol: natural := 0;
                variable c: natural := 0;
                variable d: natural := 0;
                variable n: natural := 0;
                variable c_init: natural := 0;
                --  screen cursor
                variable px_X: natural := 0;
                variable px_Y: natural := 0;
                variable char_X: natural := 0;
                variable char_Y: natural := 0;
                variable px_X_lim: natural := 0;
                variable px_Y_lim: natural := 0;
                --  other
                variable v: std_logic_vector(7 downto 0) := (others=>'0');
            begin
                if (rising_edge(sysClk)) then
                    if (sysRstb='0') then
                        r_m_stage <= s_M_INIT;
                    else
                        case (r_m_stage) is
                            when s_M_INIT =>
                                c := 0;
                                px_X := 0;
                                px_Y := 0;
                                char_X := 0;
                                char_Y := 0;
                                --  setting the colors
                                r_colors(11 downto 0) <= x"888";    --  text in grey
                                r_colors(23 downto 12) <= x"008";   --  background in light blue
                                --  going
                                r_m_jump <= s_M_SYM_2;
                                r_m_stage <= s_M_IDLE;
                            
                            when s_M_IDLE =>
                                --  now we wait for something to happen on the bus
                                cond := ss_dev_out_drdy & ss_dev_chg;
                                case (cond) is
                                    when "00" =>
                                        --  idle
                                        r_m_stage <= s_M_IDLE;
                                                                                                                
                                    when "01" =>
                                        --  local registers
                                        r_m_stage <= s_M_REG;
                                    
                                    when "10" =>
                                        --  virtual register event
                                        if (ss_dev_out_cmd='0') then
                                            --  write command : this can work
                                            r_m_stage <= s_M_VRT_0;
                                        else
                                            --  read command -> not supported at the moment due to memory implementation limitation
                                            r_m_stage <= s_M_VRT_0_R;
                                        end if;
                                    
                                    --  impossible cases here
                                    when others =>
                                        r_m_stage <= s_M_IDLE;
                                    
                                end case;
                            
                            when s_M_REG =>
                                if (ss_dev_chg='0') then
                                    r_dev_in_latch <= '0';
                                    r_m_stage <= s_M_IDLE;
                                else
                                    r_dev_in_latch <= '1';
                                    r_m_stage <= s_M_REG;
                                end if;
                            
                            when s_M_VRT_0 =>
                                addr := to_integer(unsigned(ss_dev_out_addr)) - 64;
                                symbol := to_integer(unsigned(ss_dev_out_data));
                                if (addr < 33) then
                                    --  vga command
                                    r_m_stage <= s_M_CMD;
                                else
                                    addr := addr - 33;
                                    if (addr < 1896) then
                                        --  character mode: 0 to 1895
                                        --  in this case I have 11 bits that represent the position.
                                        --  the lowest 6 bits are the column index (0 to 39)
                                        --  the highest 5 bits are the row index (0 to 29)
                                        addr_binary := std_logic_vector(to_unsigned(to_integer(unsigned(ss_dev_out_addr)) - 64 - 33, 23));
                                        col := to_integer(unsigned(addr_binary(5 downto 0)));
                                        row := to_integer(unsigned(addr_binary(10 downto 6)));
                                        r_m_stage <= s_M_SYM_0;
                                    else
                                        --  pixel mode: 1896 to 124583
                                        --  in this case I have 76800 addresses over 17 bits
                                        --  the lowest 9 bits are the column index (0 to 319)
                                        --  the highest 8 bits are the row index (0 to 239)
                                        addr_binary := std_logic_vector(to_unsigned(to_integer(unsigned(ss_dev_out_addr)) - 64 - 33 - 1896, 23));
                                        col := to_integer(unsigned(addr_binary(8 downto 0)));
                                        row := to_integer(unsigned(addr_binary(16 downto 9)));
                                        r_m_stage <= s_M_PX_0;                                        
                                    end if;
                                end if;
                            
                            when s_M_VRT_0_R =>
                                --  we just need to answer back with zeros
                                r_dev_in_data <= (others=>'0');
                                r_m_stage <= s_M_SYM_2;
                                
                            when s_M_SYM_0 =>
                                --  I now simply have to read the character rom and place the character in the internal screen memory
                                --  to to this I need to edit 8 bytes
                                char_X := col;
                                char_Y := row;
                                if (video_memory_active='0') then
                                    video_memory(row*8 + c)(((col+1)*8)-1 downto col*8) <= character_rom(symbol*8 + c);
                                    r_m_stage <= s_M_SYM_1;
                                else
                                    --  waiting for vram to be free
                                    r_m_stage <= s_M_SYM_0;
                                end if;
                            
                            when s_M_SYM_1 =>
                                if (c=7) then
                                    --  placed everything
                                    c := 0;
                                    r_m_stage <= r_m_jump;
                                else
                                    --  still need to place
                                    c := c + 1;
                                    r_m_stage <= s_M_SYM_0;
                                end if;
                            
                            when s_M_SYM_2 =>
                                if (ss_dev_out_drdy='0') then
                                    --  done and updating
                                    r_dev_in_latch <= '0';
                                    r_m_stage <= s_M_IDLE;
                                else
                                    --  waiting
                                    r_dev_in_latch <= '1';
                                    r_m_stage <= s_M_SYM_2;
                                end if;
                                
                            --  in case of pixel manipulation
                            when s_M_PX_0 =>
                                px_X := col;
                                px_Y := row;
                                if (video_memory_active='0') then
                                    video_memory(row)(col) <= ss_dev_out_data(0);
                                    r_m_stage <= s_M_SYM_2;
                                else
                                    --  waiting
                                    r_m_stage <= s_M_PX_0;
                                end if;
                            
                            --  vga command
                            when s_M_CMD =>
                                --  we have to check what kind of command
                                case (addr) is
                                    when 0 =>
                                        --  command 0: clear the screen
                                        px_X := 0;
                                        px_Y := 0;
                                        char_X := 0;
                                        char_Y := 0;
                                        --  setting the clear values
                                        c_init := 0;
                                        c := 0;
                                        d := 0;
                                        px_X_lim := 239;
                                        px_Y_lim := 159;
                                        r_m_stage <= s_M_CMD_0;
                                    
                                    -------------------------------------------------------------------------------
                                    --  CHARACTER MODE COMMANDS
                                    --
                                    when 1 =>
                                        --  command 1: character mode, clear the current line                                        
                                        px_X_lim := 239;
                                        px_Y_lim := 8*char_Y + 7;
                                        c_init := 0;
                                        c := 0;
                                        d := 8*char_Y;
                                        r_m_stage <= s_M_CMD_0;
                                    
                                    when 2 =>
                                        --  command 2: character mode, clear the current column
                                        px_X_lim := 8*char_X + 7;
                                        px_Y_lim := 159;
                                        c_init := 8*char_X;
                                        c := 8*char_X;
                                        d := 0;
                                        r_m_stage <= s_M_CMD_0;
                                    
                                    when 3 =>
                                        --  command 3: character mode, set the cursor to home (0,0)
                                        char_X := 0;
                                        char_Y := 0;
                                        r_m_stage <= s_M_SYM_2;
                                    
                                    when 4 =>
                                        --  command 4: character mode, advance cursor by N cells to the right
                                        if ((char_X + symbol) < 30) then
                                            char_X := char_X + symbol;
                                        else
                                            char_X := 29;
                                        end if;
                                        r_m_stage <= s_M_SYM_2;
                                    
                                    when 5 =>
                                        --  command 5: character mode, advance cursor by N cells to the left
                                        if (char_X < symbol) then
                                            char_X := 0;
                                        else
                                            char_X := char_X - symbol;
                                        end if;
                                        r_m_stage <= s_M_SYM_2;
                                    
                                    when 6 =>
                                        --  command 6: character mode, advance cursor by N cells up
                                        if (char_Y < symbol) then
                                            char_Y := 0;
                                        else
                                            char_Y := char_Y - symbol;
                                        end if;
                                        r_m_stage <= s_M_SYM_2;
                                    
                                    when 7 =>
                                        --  command 7: character mode, advance cursor by N cells down
                                        if ((char_Y + symbol) < 20) then
                                            char_Y := char_Y + symbol;
                                        else
                                            char_Y := 19;
                                        end if;
                                        r_m_stage <= s_M_SYM_2;
                                    
                                    when 8 =>
                                        --  command 8: character mode, place character and advance by 1 to the right
                                        r_m_jump <= s_M_CMD_8;
                                        col := char_X;
                                        row := char_Y;
                                        d := 0;
                                        r_m_stage <= s_M_SYM_0;
                                    
                                    when 9 =>
                                        --  command 9: character mode, place character and advance by 1 to the left
                                        r_m_jump <= s_M_CMD_8;
                                        col := char_X;
                                        row := char_Y;
                                        d := 1;
                                        r_m_stage <= s_M_SYM_0;
                                    
                                    when 10 =>
                                        --  command 10: character mode, place character and advance by 1 up
                                        r_m_jump <= s_M_CMD_8;
                                        col := char_X;
                                        row := char_Y;
                                        d := 2;
                                        r_m_stage <= s_M_SYM_0;
                                    
                                    when 11 =>
                                        --  command 11: character mode, place character and advance by 1 down
                                        r_m_jump <= s_M_CMD_8;
                                        col := char_X;
                                        row := char_Y;
                                        d := 3;
                                        r_m_stage <= s_M_SYM_0;
                                    
                                    when 12 =>
                                        --  command 12: character mode, go left by 1 and place character
                                        if (char_X < 1) then
                                            char_X := 0;
                                        else
                                            char_X := char_X - 1;
                                        end if;
                                        r_m_stage <= s_M_CMD_9;
                                    
                                    when 13 =>
                                        --  command 13: character mode, go right by 1 and and place character
                                        if ((char_X + 1) < 30) then
                                            char_X := char_X + 1;
                                        else
                                            char_X := 29;
                                        end if;
                                        r_m_stage <= s_M_CMD_9;
                                    
                                    when 14 => 
                                        --  command 14: character mode, go down by 1 and place character
                                        if ((char_Y + 1) < 20) then
                                            char_Y := char_Y + 1;
                                        else
                                            char_Y := 19;
                                        end if;
                                        r_m_stage <= s_M_CMD_9;
                                    
                                    when 15 =>
                                        --  command 15: character mode, go up by 1 and place character
                                        if (char_Y < 1) then
                                            char_Y := 0;
                                        else
                                            char_Y := char_Y - 1;
                                        end if;
                                        r_m_stage <= s_M_CMD_9;
                                    
                                    when 16 =>
                                        --  command 16: character mode, carriage return and go back to beginning of line
                                        if ((char_Y + 1) < 20) then
                                            char_Y := char_Y + 1;
                                        else
                                            char_Y := 19;
                                        end if;
                                        char_X := 0;
                                        r_m_stage <= s_M_SYM_2;
                                    
                                    when 17 =>
                                        --  command 17: character mode: set background color of this cell
                                        r_colors(19 downto 12) <= ss_dev_out_data;
                                        r_m_stage <= s_M_SYM_2;
                                    
                                    when 18 =>
                                        --  command 18: character mode: set foreground color of this cell
                                        r_colors(7 downto 0) <= ss_dev_out_data;
                                        r_m_stage <= s_M_SYM_2;
                                    
                                    when 19 =>
                                        --  command 19: character mode: reset background color of this cell
                                        r_colors(23 downto 12) <= x"008";
                                        r_m_stage <= s_M_SYM_2;
                                    
                                    when 20 =>
                                        --  command 20: character mode, reset foreground color of this cell
                                        r_colors(11 downto 0) <= x"888";
                                        r_m_stage <= s_M_SYM_2;
                                    
                                    -------------------------------------------------------------------------------
                                    --  PIXEL MODE COMMANDS
                                    --
                                    when 21|22 =>
                                        --  command 21: clear current pixel
                                        px_X_lim := px_X + 1;
                                        px_Y_lim := px_Y;
                                        c := px_X;
                                        d := px_Y;
                                        c_init := 0;
                                        r_m_stage <= s_M_CMD_0;
                                    
                                    when 23 =>
                                        --  command 23: set current pixel and go right by 1
                                        r_m_jump <= s_M_CMD_11;
                                        px_X_lim := px_X + 1;
                                        px_Y_lim := px_Y;
                                        c := px_X;
                                        d := px_Y;
                                        c_init := 0;
                                        n := 0;
                                        r_m_stage <= s_M_CMD_0;
                                    
                                    when 24 =>
                                        --  command 24: set current pixel and go left by 1
                                        r_m_jump <= s_M_CMD_11;
                                        px_X_lim := px_X + 1;
                                        px_Y_lim := px_Y;
                                        c := px_X;
                                        d := px_Y;
                                        c_init := 0;
                                        n := 1;
                                        r_m_stage <= s_M_CMD_0;
                                    
                                    when 25 =>
                                        --  command 25: set current pixel and go up by 1
                                        r_m_jump <= s_M_CMD_11;
                                        px_X_lim := px_X + 1;
                                        px_Y_lim := px_Y;
                                        c := px_X;
                                        d := px_Y;
                                        c_init := 0;
                                        n := 2;
                                        r_m_stage <= s_M_CMD_0;
                                    
                                    when 26 =>
                                        --  command 26: set current pixel and go down by 1
                                        r_m_jump <= s_M_CMD_11;
                                        px_X_lim := px_X + 1;
                                        px_Y_lim := px_Y;
                                        c := px_X;
                                        d := px_Y;
                                        c_init := 0;
                                        n := 3;
                                        r_m_stage <= s_M_CMD_0;
                                    
                                    when 27 =>
                                        --  command 27: go left by 1 and set current pixel
                                        if (px_X < 1) then
                                            px_X := 0;
                                        else
                                            px_X := px_X - 1;
                                        end if;
                                        px_X_lim := px_X + 1;
                                        px_Y_lim := px_Y;
                                        c := px_X;
                                        d := px_Y;
                                        c_init := 0;
                                        r_m_stage <= s_M_CMD_0;
                                    
                                    when 28 =>
                                        --  command 28: go right by 1 and set current pixel
                                        if ((px_X + 1) < 240) then
                                            px_X := px_X + 1;
                                        else
                                            px_X := 239;
                                        end if;
                                        px_X_lim := px_X + 1;
                                        px_Y_lim := px_Y;
                                        c := px_X;
                                        d := px_Y;
                                        c_init := 0;
                                        r_m_stage <= s_M_CMD_0;
                                    
                                    when 29 =>
                                        --  command 29: go down by 1 and set current pixel
                                        if ((px_Y + 1) < 160) then
                                            px_Y := px_Y + 1;
                                        else
                                            px_Y := 159;
                                        end if;
                                        px_X_lim := px_X + 1;
                                        px_Y_lim := px_Y;
                                        c := px_X;
                                        d := px_Y;
                                        c_init := 0;
                                        r_m_stage <= s_M_CMD_0;
                                    
                                    when 30 =>
                                        --  command 30: go up by 1 and set current pixel
                                        if (px_Y < 1) then
                                            px_Y := 0;
                                        else
                                            px_Y := px_Y - 1;
                                        end if;
                                        px_X_lim := px_X + 1;
                                        px_Y_lim := px_Y;
                                        c := px_X;
                                        d := px_Y;
                                        c_init := 0;
                                        r_m_stage <= s_M_CMD_0;
                                    
                                    when 31 =>
                                        --  command 31: clear current pixel row
                                        px_X := 0;
                                        px_X_lim := 239;
                                        px_Y_lim := px_Y;
                                        c := 0;
                                        d := px_Y;
                                        c_init := 0;
                                        r_m_stage <= s_M_CMD_12;
                                    
                                    when 32 =>
                                        --  command 32: clear current pixel col
                                        c := px_X;
                                        c_init := px_X;
                                        d := 0;
                                        px_Y := 0;                                        
                                        px_X_lim := px_X + 1;
                                        px_Y_lim := 159;
                                        r_m_stage <= s_M_CMD_13;
                                    
                                    when others =>
                                        null;
                                end case;
                            
                            when s_M_CMD_0 =>
                                --  purges the video memory
                                if (video_memory_active='0') then
                                    if (c=px_X_lim) then
                                        if (d=px_Y_lim) then
                                            --  end of the purge command
                                            c := 0;
                                            d := 0;
                                            r_m_stage <= r_m_jump;
                                        else
                                            --  next line
                                            c := c_init;
                                            d := d + 1;
                                            r_m_stage <= s_M_CMD_0;
                                        end if;
                                    else
                                        --  clearing video
                                        video_memory(d)(c) <= '0';
                                        c := c + 1;
                                        r_m_stage <= s_M_CMD_0;
                                    end if;
                                else
                                    --  must wait for video memory to become available
                                    r_m_stage <= s_M_CMD_0;
                                end if;
                            
                            when s_M_CMD_8 =>
                                --  now we advance by 1                               
                                r_m_jump <= s_M_SYM_2;
                                case (d) is
                                    when 0 =>
                                        --  need to advance by 1 to the right
                                        if ((char_X + 1) < 30) then
                                            char_X := char_X + 1;
                                        else
                                            char_X := 29;
                                        end if;
                                    
                                    when 1 =>
                                        --  need to advance by 1 to the left
                                        if (char_X < 1) then
                                            char_X := 0;
                                        else
                                            char_X := char_X - 1;
                                        end if;
                                    
                                    when 2 =>
                                        --  need to advance 1 upwards
                                        if (char_Y < 1) then
                                            char_Y := 0;
                                        else
                                            char_Y := char_Y - 1;
                                        end if;
                                    
                                    when 3 =>
                                        --  need to advance 1 downwards
                                        if ((char_Y + 1) < 20) then
                                            char_Y := char_Y + 1;
                                        else
                                            char_Y := 19;
                                        end if;
                                    
                                    when others =>
                                        null;
                                end case;
                                r_m_stage <= s_M_SYM_2;
                            
                            when s_M_CMD_9 =>
                                col := char_X;
                                row := char_Y;
                                r_m_stage <= s_M_SYM_0;
                            
                            when s_M_CMD_11 =>
                                r_m_jump <= s_M_SYM_2;
                                case (d) is
                                    when 0 =>
                                        --  go to the right by one
                                        if ((px_X + 1) < 240) then
                                            pX_X := px_X + 1;
                                        else
                                            px_X := 239;
                                        end if;
                                    
                                    when 1 =>
                                        --  go to the left by one
                                        if (px_X < 1) then
                                            px_X := 0;
                                        else
                                            px_X := px_X - 1;
                                        end if;
                                    
                                    when 2 =>
                                        --  go upwards by one
                                        if (px_Y < 1) then
                                            px_Y := 0;
                                        else
                                            px_Y := px_Y - 1;
                                        end if;
                                    
                                    when 3 =>
                                        --  go downwards by one
                                        if ((px_Y + 1) < 160) then
                                            px_Y := px_Y + 1;
                                        else
                                            px_Y := 159;
                                        end if;
                                    
                                    when others =>
                                        null;
                                end case;
                                r_m_stage <= s_M_SYM_2;
                                                            
                            when others =>
                                r_m_stage <= s_M_IDLE;
                        end case;
                    end if;
                end if;
            end process MAIN;
            
end Behavioral;

--Horizontal timing (line)
--Polarity of horizontal sync pulse is negative.

--Scanline part	Pixels	Time [µs]
--Visible area	640	25.422045680238
--Front porch	16	0.63555114200596
--Sync pulse	96	3.8133068520357
--Back porch	48	1.9066534260179
--Whole line	800	31.777557100298
--Vertical timing (frame)
--Polarity of vertical sync pulse is negative.

--Frame part	Lines	Time [ms]
--Visible area	480	15.253227408143
--Front porch	10	0.31777557100298
--Sync pulse	2	0.063555114200596
--Back porch	33	1.0486593843098
--Whole frame	525	16.683217477656