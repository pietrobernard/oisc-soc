library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

--  this subdev belongs to the 'I2C subsystem' and it drives the i2c display
entity subdev_I2C_dev1_v2 is
    generic (
        --  bus topology
        bus_width: integer := 32;
        data_width: integer := 8;
        addr_width: integer := 23;
        --  hardware id for the UART
        --  this allows for data-packets sent from the uart device to reach this and not other sub-devs of the uart
        hw_id: integer := 1;
        hw_i2c_addr: std_logic_vector(6 downto 0) := std_logic_vector(to_unsigned(39, 7));
        --  device manager setup
        dev_id: integer := 1;
        local_mem_begin: integer := 0;      --  start of memory space
        local_mem_nvrt: integer := 0;       --  number of virtual registers
        sram_mem_begin: integer := 0;       --  start of sram range (lies outside of the local memory range defined above)
        sram_mem_end: integer := 0;         --  end of sram range
        regcfg: string := "generic.mem"     --  logical registers configuration file
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  sub-system signals
        bus_lines: inout std_logic_vector(bus_width-1 downto 0);
        bus_strobe_M: inout std_logic;
        bus_strobe_S: inout std_logic;
        bus_keep: inout std_logic;
        bus_done_S: inout std_logic;
        bus_rq: out std_logic;
        bus_grant: in std_logic;
        bus_busy: in std_logic;
        --  booking system
        bus_req_sys: out std_logic;         --  this line must be driven high if one of the peripherals wants to acquire the mainbus
        bus_rdy_sys: in std_logic;          --  this line will go high if the system bus has been granted
        bus_err_sys: in std_logic;
        --  hardware databus lanes
        hw_bus_rq: out std_logic;
        hw_bus_grant: in std_logic;
        hw_bus_busy: in std_logic;
        hw_data_to: out std_logic_vector(7 downto 0);
        hw_keep: out std_logic;
        hw_latch: out std_logic;
        hw_done: in std_logic;
        hw_data_from: in std_logic_vector(7 downto 0);
        hw_drdy: in std_logic;
        hw_ack: out std_logic;
        --  debug
        dbg_stage: out natural
    );
end subdev_I2C_dev1_v2;

architecture Behavioral of subdev_I2C_dev1_v2 is
    --  debug
    signal r_dbg: natural := 0;
    
    --  subdev interface
    signal r_bus_in_cmd: std_logic := '0';
    signal r_bus_in_addr: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal r_bus_in_data: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal r_bus_in_keep: std_logic := '0';
    signal r_bus_in_latch: std_logic := '0';
    
    --  samplig hw bus
    signal ss_hw_bus_grant: std_logic := '0';
    signal ss_hw_bus_busy: std_logic := '0';
    signal ss_hw_done: std_logic := '0';
    signal ss_hw_drdy: std_logic := '0';
    
    --  sampling sub-bus
    signal s_bus_out_cmd: std_logic;
    signal s_bus_out_addr: std_logic_vector(addr_width-1 downto 0);
    signal s_bus_out_data: std_logic_vector(data_width-1 downto 0);
    signal s_bus_out_drdy: std_logic;
    signal s_bus_out_done: std_logic;
    signal s_bus_err: std_logic;
    signal s_bus_chg: std_logic;
    signal ss_bus_out_cmd: std_logic := '0';        
    signal ss_bus_out_drdy: std_logic := '0';
    signal ss_bus_out_done: std_logic := '0';
    signal ss_bus_out_addr: std_logic_vector(addr_width-1 downto 0);
    signal ss_bus_out_data: std_logic_vector(data_width-1 downto 0);
    signal ss_bus_err: std_logic := '0';
    signal ss_bus_chg: std_logic := '0';
    
    --  hardware bus drivers
    signal r_hw_bus_dir: std_logic := '0';
    signal r_hw_bus_rq: std_logic := '0';
    signal r_hw_bus_data_to: std_logic_vector(7 downto 0) := (others=>'0');
    signal r_hw_bus_keep: std_logic := '0';
    signal r_hw_bus_latch: std_logic := '0';
    signal r_hw_bus_ack: std_logic := '0';
    
    --  state machine
    type t_SM is (s_INIT, s_WAIT, s_INITDEV_0, s_INITDEV_1, s_INITDEV_2, s_INITDEV_3, s_IDLE, s_CMD, s_REG, s_CMDEXEC_0, s_CMDEXEC_1, s_CMDEXEC_2);
    signal r_stage: t_SM := s_INIT;
    signal r_jump: t_SM;
    
    --  data components for the eeprom
    signal i2c_cmd_addr: std_logic_vector(7 downto 0);
    signal i2c_devreg: std_logic_vector(15 downto 0);
    
    --  display initialization sequence
    type RAM_ARRAY is array (0 to 41 ) of std_logic_vector (7 downto 0);
    signal lcd_data: RAM_ARRAY := ( 
                                    x"38", x"34", x"30",
                                    x"38", x"34", x"30",
                                    x"38", x"34", x"30",
                                    x"28", x"24", x"20",
                                    x"28", x"24", x"20",
                                    x"88", x"84", x"80",
                                    x"08", x"04", x"00",
                                    x"f8", x"f4", x"f0",
                                    x"08", x"04", x"00",
                                    x"18", x"14", x"10",
                                    x"08", x"04", x"00",
                                    x"68", x"64", x"60",
                                    x"08", x"04", x"00",
                                    x"28", x"24", x"28"
                                    );
    
    --  i2c init stuff
    type I2C_INIT is array (0 to 3) of std_logic_vector (7 downto 0);
    signal i2c_packet: I2C_INIT := (x"00", x"00", x"00",x"00");

    --  some commands
    type I2C_PACK is array (0 to 5) of std_logic_vector (7 downto 0);        
    signal lcd_clear: I2C_PACK := (x"08",x"0c",x"08",x"18",x"1c",x"18");
    signal lcd_home: I2C_PACK := (x"08",x"0c",x"08",x"28",x"2c",x"28");
    signal lcd_coff: I2C_PACK := (x"08",x"0c",x"08",x"c8",x"cc",x"c8");
    signal lcd_con: I2C_PACK := (x"08",x"0c",x"08",x"f8",x"fc",x"f8");
    signal lcd_mleft: I2C_PACK := (x"08",x"0c",x"08",x"88",x"8c",x"88");
    signal lcd_mright: I2C_PACK := (x"08",x"0c",x"08",x"c8",x"cc",x"c8");
    signal lcd_newline: I2C_PACK := (x"c8",x"cc",x"c8",x"08",x"0c",x"08");
    signal lcd_command: I2C_PACK;
        
    --  synchro
    signal ss_sync_0: std_logic := '0';
begin
    --  shared lines drivers for hardware driver
    HWBUS_DATA_DRV: entity work.buffer_nbits(Behavioral) generic map (w => 8) port map(d => r_hw_bus_data_to, q => hw_data_to, oe=>r_hw_bus_dir);
    HWBUS_KEEP_DRV: entity work.buffer_nbits(Behavioral) generic map (w => 1) port map(d(0) => r_hw_bus_keep, q(0) => hw_keep, oe=>r_hw_bus_dir);
    HWBUS_LATCH_DRV:entity work.buffer_nbits(Behavioral) generic map (w => 1) port map(d(0) => r_hw_bus_latch, q(0) => hw_latch, oe=>r_hw_bus_dir);
    HWBUS_ACK_DRV:  entity work.buffer_nbits(Behavioral) generic map (w => 1) port map(d(0) => r_hw_bus_ack, q(0) => hw_ack, oe=>r_hw_bus_dir);

    --  continuous assignment
    hw_bus_rq <= r_hw_bus_rq;

    --  subbus to interface with the central system
    SBUSINT:    entity work.subbus_dev_v2(Behavioral)
                generic map (
                    dev_id => dev_id,
                    local_mem_begin => local_mem_begin,
                    local_mem_nvrt => local_mem_nvrt,
                    regcfg => regcfg
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  system bus interface signals
                    bus_lines => bus_lines,
                    bus_strobe_M => bus_strobe_M,
                    bus_strobe_S => bus_strobe_S,
                    bus_keep => bus_keep,
                    bus_done_S => bus_done_S,
                    bus_rq => bus_rq,
                    bus_grant => bus_grant,
                    bus_busy => bus_busy,
                    --  addendum for the sub-dev
                    bus_req_sys => bus_req_sys,
                    bus_rdy_sys => bus_rdy_sys,
                    bus_err_sys => bus_err_sys,
                    --  interface signals
                    dev_in_cmd => r_bus_in_cmd,
                    dev_in_addr => r_bus_in_addr,
                    dev_in_data => r_bus_in_data,
                    dev_in_keep => r_bus_in_keep,
                    dev_in_latch => r_bus_in_latch,
                    dev_out_cmd => s_bus_out_cmd,   --  output command
                    dev_out_addr => s_bus_out_addr, --  output address
                    dev_out_data => s_bus_out_data, --  output data
                    dev_out_drdy => s_bus_out_drdy, --  when new data arrives
                    dev_out_done => s_bus_out_done, --  when no more transactions
                    dev_err => s_bus_err,           --  if an error occurrs
                    dev_chg => s_bus_chg            --  when an operation on local physical registers completes
                );
            
    --  main sampling and driving processes: this processese listens for bus and hardware events and acts accordingly
    SAMPLER:    process(sysClk)
                begin
                    if (rising_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                ss_bus_chg <= '0';
                                ss_bus_out_drdy <= '0';
                                ss_sync_0 <= '0';
                            
                            when s_INITDEV_0 =>
                                ss_hw_bus_grant <= hw_bus_grant;
                                                                                    
                            when s_INITDEV_1 =>
                                ss_hw_drdy <= hw_drdy;
                            
                            when s_INITDEV_2 =>
                                ss_hw_drdy <= hw_drdy;
                            
                            when s_INITDEV_3 =>
                                ss_hw_bus_grant <= hw_bus_grant;
                            
                            when s_IDLE =>
                                ss_bus_chg <= s_bus_chg;
                                ss_bus_out_drdy <= s_bus_out_drdy;
                                ss_bus_out_done <= s_bus_out_done;
                                ss_bus_out_addr <= s_bus_out_addr;
                                ss_bus_out_data <= s_bus_out_data;
                                ss_bus_out_cmd <= s_bus_out_cmd;
                                ss_sync_0 <= '0';
                            
                            when s_CMDEXEC_0 =>
                                ss_bus_out_drdy <= s_bus_out_drdy;
                            
                            when s_REG =>
                                ss_bus_chg <= s_bus_chg;
                                                                                                                                                
                            when others =>
                                null;
                        end case;
                    end if;
                end process SAMPLER;

    MAIN:       process(sysClk)
                    variable cond: std_logic_vector(1 downto 0) := "00";
                    variable addr_bits: std_logic_vector(15 downto 0) := (others=>'0');
                    variable addr: natural := 0;
                    variable pc: natural := 0;
                    variable gc: natural := 0;
                    variable pc_lim: natural := 0;
                    variable gc_lim: natural := 0;
                    variable isInit: natural := 0;
                    variable data: std_logic_vector(7 downto 0) := (others=>'0');
                    variable H_bits: std_logic_vector(7 downto 0) := (others=>'0');
                    variable L_bits: std_logic_vector(7 downto 0) := (others=>'0');
                    variable HL_bits: std_logic_vector(7 downto 0) := (others=>'0');
                    variable COL: std_logic_vector(4 downto 0) := (others=>'0');
                    variable ROW: std_logic_vector(1 downto 0) := (others=>'0');
                    variable BADDR: natural := 0;
                    variable a: natural := 0;
                    variable b: natural := 0;
                    variable delay: natural := 0;
                    variable c_delay: natural := 0;
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            r_stage <= s_INIT;
                        else
                            case (r_stage) is
                                when s_INIT =>
                                    --  initializing hardware controls
                                    r_hw_bus_dir <= '0';
                                    r_hw_bus_rq <= '0';
                                    r_hw_bus_data_to <= (others=>'0');
                                    r_hw_bus_keep <= '0';
                                    r_hw_bus_latch <= '0';
                                    r_hw_bus_ack <= '0';
                                    --  initializing bus controls
                                    r_bus_in_cmd <= '0';
                                    r_bus_in_addr <= (others=>'0');
                                    r_bus_in_data <= (others=>'0');
                                    r_bus_in_keep <= '0';
                                    r_bus_in_latch <= '0';
                                    --  stage
                                    pc := 0;
                                    gc := 0;
                                    pc_lim := 42;
                                    gc_lim := 4;
                                    isInit := 0;
                                    COL := (others=>'0');
                                    ROW := (others=>'0');
                                    delay := 0;
                                    c_delay := 0;
                                    r_jump <= s_IDLE;
                                    --  going
                                    r_stage <= s_INITDEV_0;
                                
                                when s_INITDEV_0 =>
                                    --  acquiring the hardware bus
                                    if (ss_hw_bus_grant='1') then
                                        --  we have the bus, so we can initialize
                                        r_hw_bus_data_to <= (others=>'0');
                                        r_hw_bus_keep <= '0';
                                        r_hw_bus_latch <= '0';
                                        r_hw_bus_ack <= '0';
                                        r_hw_bus_dir <= '1';
                                        --  building the datapacket
                                        i2c_packet(0)(7) <= '0';
                                        i2c_packet(0)(6 downto 0) <= hw_i2c_addr;
                                        i2c_packet(1) <= (others=>'0');
                                        i2c_packet(2) <= std_logic_vector(to_unsigned(pc_lim, 8));
                                        if (isInit=0) then
                                            i2c_packet(3) <= lcd_data(pc);
                                        else
                                            i2c_packet(3) <= lcd_command(pc);
                                        end if;
                                        r_stage <= s_INITDEV_1;
                                    else
                                        r_hw_bus_rq <= '1';
                                        r_stage <= s_INITDEV_0;
                                    end if;
                                
                                when s_INITDEV_1 =>
                                    if (ss_hw_drdy='1') then
                                        --  done
                                        if ((isInit=0) and (gc=(gc_lim-1))) then
                                            r_stage <= s_CMDEXEC_2;
                                        else
                                            r_stage <= s_INITDEV_2;
                                        end if;
                                    else
                                        --  going
                                        r_hw_bus_data_to <= i2c_packet(gc);
                                        r_hw_bus_latch <= '1';
                                        r_stage <= s_INITDEV_1;
                                    end if;
                               
                                when s_INITDEV_2 =>
                                    if (ss_hw_drdy='0') then
                                        if (gc=(gc_lim-1)) then
                                            --  now we've reached number 3 which is the initialization data, and we must continue writing into it
                                            if (pc=(pc_lim-1)) then
                                                --  we're done with the whole thing, so
                                                gc := 0;
                                                pc := 0;
                                                pc_lim := 0;
                                                --  going to idle
                                                r_stage <= s_INITDEV_3;
                                            else
                                                --  initialization sequence
                                                pc := pc + 1;
                                                if (isInit=0) then
                                                    i2c_packet(gc) <= lcd_data(pc);
                                                else
                                                    i2c_packet(gc) <= lcd_command(pc);
                                                end if;
                                                --  going
                                                r_stage <= s_INITDEV_1;
                                            end if;
                                        else
                                            --  it will proceed with another
                                            gc := gc + 1;
                                            r_stage <= s_INITDEV_1;
                                        end if;
                                    else
                                        --  questa linea sotto e' stata spostata dalla corrispondente che era su INITDEV_1.
                                        r_hw_bus_latch <= '0';
                                        r_stage <= s_INITDEV_2;
                                    end if;
                                
                                when s_INITDEV_3 =>
                                    if (ss_hw_bus_grant='0') then
                                        --  going
                                        r_stage <= r_jump;
                                    else
                                        --  releasing the hardware bus
                                        r_hw_bus_rq <= '0';
                                        r_hw_bus_data_to <= (others=>'0');
                                        r_hw_bus_keep <= '0';
                                        r_hw_bus_latch <= '0';
                                        r_hw_bus_ack <= '0';
                                        r_hw_bus_dir <= '0';
                                        --  waiting
                                        r_stage <= s_INITDEV_3;
                                    end if;
                                
                                when s_IDLE =>
                                    cond := (ss_bus_chg & ss_bus_out_drdy);
                                    isInit := 1;
                                    case (cond) is
                                        when "01" =>
                                            --  virtual event
                                            if (ss_bus_out_cmd='0') then
                                                --   it is a write
                                                r_stage <= s_CMD;
                                            else
                                                --  it is a read
                                                --  reading here is not supported, so we must always return a zero, hence
                                                r_bus_in_data <= (others=>'0');
                                                r_bus_in_keep <= '0';
                                                r_stage <= s_CMDEXEC_0;
                                            end if;
                                        
                                        when "10" =>
                                            r_stage <= s_REG;
                                        
                                        when others =>
                                            r_stage <= s_IDLE;
                                    end case;
                                
                                when s_CMD =>
                                    --  virtual event
                                    addr := to_integer(unsigned(ss_bus_out_addr)) - 64;
                                    r_dbg <= addr;
                                    --  comandi disponibili:
                                    --  clear display
                                    --  return home for the cursor
                                    --  turn cursor on/off
                                    --  turn cursor blink on/off
                                    --  set cursor
                                    --  
                                    if (addr < 10) then
                                        case (addr) is
                                            when 0 =>
                                                --  virtual address 0 is to clear the display
                                                --  x"08",x"0c",x"08",x"18",x"1c",x"18"
                                                lcd_command <= lcd_clear;
                                                pc := 0;
                                                pc_lim := 6;
                                                delay := 200000;
                                                r_jump <= s_CMDEXEC_0;
                                                r_stage <= s_INITDEV_0;
                                            
                                            when 1 =>
                                                --  return home
                                                --  x"08",x"0c",x"08",x"28",x"2c",x"28"
                                                COL := (others=>'0');
                                                ROW := "00";
                                                lcd_command <= lcd_home;
                                                pc := 0;
                                                pc_lim := 6;
                                                delay := 200000;
                                                r_jump <= s_CMDEXEC_0;
                                                r_stage <= s_INITDEV_0;
                                            
                                            when 2 =>
                                                --  cursor on/off
                                                -- off: 0x08 |  LCD_DISPLAYON | LCD_CURSOROFF | LCD_BLINKOFF = 0x08 | 0x04 | 0x00 | 0x00 = 0x0c : x"08",x"0c",x"08",x"c8",x"cc",x"c8",
                                                -- on : 0x08 |  LCD_DISPLAYON | LCD_CURSORON  | LCD_BLINKON = 0x0f : x"08",x"0c",x"08",x"f8",x"fc",x"f8",
                                                if (ss_bus_out_data="00000000") then
                                                    lcd_command <= lcd_coff;
                                                else
                                                    lcd_command <= lcd_con;
                                                end if;
                                                pc := 0;
                                                pc_lim := 6;
                                                delay := 4000;
                                                r_jump <= s_CMDEXEC_0;
                                                r_stage <= s_INITDEV_0; 
                                            
                                            when 3 =>                                 
                                                --  scroll display left/right
                                                --  left: 0x08 | 0x08 | 0x00 = 0x08 :   x"08",x"0c",x"08",x"88",x"8c",x"88"
                                                --  right: 0x08 | 0x08 | 0x04 = 0x0c:   x"08",x"0c",x"08",x"c8",x"cc",x"c8"
                                                if (ss_bus_out_data="00000000") then
                                                    lcd_command <= lcd_mleft;
                                                else
                                                    lcd_command <= lcd_mright;
                                                end if;
                                                pc := 0;
                                                pc_lim := 6;
                                                delay := 4000;
                                                r_jump <= s_CMDEXEC_0;
                                                r_stage <= s_INITDEV_0;
                                            
                                            when 4 =>
                                                --  place character and newline check                                                        
                                                data := ss_bus_out_data;
                                                r_dbg <= to_integer(unsigned(ss_bus_out_data));
                                                if (data=x"0a") then
                                                    --  new line
                                                    COL := (others=>'0');
                                                    ROW := "01";
                                                    lcd_command <= lcd_newline;
                                                else
                                                    H_bits := (x"01" or (data(7 downto 4)&"0000"));
                                                    L_bits := (x"01" or (data(3 downto 0)&"0000"));
                                                    lcd_command(0) <= H_bits or x"08";
                                                    lcd_command(1) <= (H_bits or x"04") or x"08";
                                                    lcd_command(2) <= (H_bits and x"fb") or x"08";
                                                    lcd_command(3) <= L_bits or x"08";
                                                    lcd_command(4) <= (L_bits or x"04") or x"08";
                                                    lcd_command(5) <= (L_bits and x"fb") or x"08";
                                                end if;
                                                pc := 0;
                                                pc_lim := 6;
                                                delay := 4000;
                                                r_jump <= s_CMDEXEC_0;
                                                r_stage <= s_INITDEV_0;
                                            
                                            ------------------------------------------------------------------
                                            --  CURSOR POSITION AND MOVEMENT
                                            --
                                            when 5 =>
                                                --  set cursor at specific address (command x80)
                                                --  gathering the ROW and COL to which to put the cursor to
                                                COL := ss_bus_out_data(4 downto 0);
                                                ROW := ss_bus_out_data(6 downto 5);
                                                --  now need to drive the thing
                                                --  the command to set the cursor is 0x80 | address
                                                --  address = base_address + column_index
                                                case (ROW) is
                                                    when "00" =>
                                                        --  line 0 base address: x00
                                                        BADDR := to_integer(unsigned(COL));

                                                    when "01" =>
                                                        --  line 1 base address: x40
                                                        BADDR := to_integer(unsigned(COL)) + 64;
                                                    
                                                    when "10" =>
                                                        --  line 2 base address: x14
                                                        BADDR := to_integer(unsigned(COL)) + 20;
                                                    
                                                    when "11" =>
                                                        --  line 3 base address: x54
                                                        BADDR := to_integer(unsigned(COL)) + 84;
                                                end case;
                                                --  compiling the command
                                                data := std_logic_vector(to_unsigned(BADDR, 8));
                                                r_dbg <= to_integer(unsigned(data));
                                                HL_bits := data or x"80";
                                                H_bits := (HL_bits(7 downto 4)&"0000");
                                                L_bits := (HL_bits(3 downto 0)&"0000");
                                                -- se cosi non va, provo ad invertire scrivendo: (H_bits | x08) & 0xfb e vedere se cosi invece va.
                                                lcd_command(0) <= H_bits or x"08";
                                                lcd_command(1) <= (H_bits or x"04") or x"08";
                                                lcd_command(2) <= (H_bits and x"fb") or x"08";
                                                lcd_command(3) <= L_bits or x"08";
                                                lcd_command(4) <= (L_bits or x"04") or x"08";
                                                lcd_command(5) <= (L_bits and x"fb") or x"08";
                                                --  executing
                                                pc := 0;
                                                pc_lim := 6;
                                                delay := 4000;
                                                r_jump <= s_CMDEXEC_0;
                                                r_stage <= s_INITDEV_0;
                                            --
                                            when 6 =>
                                                --  move cursor up by N row(s)
                                                data := ss_bus_out_data;
                                                --  now to see the COL
                                                a := to_integer(unsigned(data));
                                                b := to_integer(unsigned(ROW));
                                                if (a > b) then
                                                    --  we are trying to go up by a quantity that surpasses the actual line, so:
                                                    ROW := "00";
                                                else
                                                    --  we set to the amount
                                                    ROW := std_logic_vector(to_unsigned(b - a, 2));
                                                end if;
                                                --  selecting the row
                                                case (ROW) is
                                                    when "00" =>
                                                        --  line 0 base address: x00
                                                        BADDR := to_integer(unsigned(COL));

                                                    when "01" =>
                                                        --  line 1 base address: x40
                                                        BADDR := to_integer(unsigned(COL)) + 64;
                                                    
                                                    when "10" =>
                                                        --  line 2 base address: x14
                                                        BADDR := to_integer(unsigned(COL)) + 20;
                                                    
                                                    when "11" =>
                                                        --  line 3 base address: x54
                                                        BADDR := to_integer(unsigned(COL)) + 84;
                                                end case;
                                                --  compiling the command
                                                data := std_logic_vector(to_unsigned(BADDR, 8));
                                                r_dbg <= to_integer(unsigned(data));
                                                HL_bits := data or x"80";
                                                H_bits := (HL_bits(7 downto 4)&"0000");
                                                L_bits := (HL_bits(3 downto 0)&"0000");
                                                -- se cosi non va, provo ad invertire scrivendo: (H_bits | x08) & 0xfb e vedere se cosi invece va.
                                                lcd_command(0) <= H_bits or x"08";
                                                lcd_command(1) <= (H_bits or x"04") or x"08";
                                                lcd_command(2) <= (H_bits and x"fb") or x"08";
                                                lcd_command(3) <= L_bits or x"08";
                                                lcd_command(4) <= (L_bits or x"04") or x"08";
                                                lcd_command(5) <= (L_bits and x"fb") or x"08";
                                                --  executing
                                                pc := 0;
                                                pc_lim := 6;
                                                delay := 4000;
                                                r_jump <= s_CMDEXEC_0;
                                                r_stage <= s_INITDEV_0;
                                            --
                                            when 7 =>
                                                --  move cursor down by one row
                                                data := ss_bus_out_data;
                                                --  now to see the COL
                                                a := to_integer(unsigned(data));
                                                b := to_integer(unsigned(ROW));
                                                if ((a + b) > 3) then
                                                    --  we cannot go beyond line 3
                                                    ROW := "11";
                                                else
                                                    ROW := std_logic_vector(to_unsigned(a + b, 2));
                                                end if;
                                                --  selecting the row
                                                case (ROW) is
                                                    when "00" =>
                                                        --  line 0 base address: x00
                                                        BADDR := to_integer(unsigned(COL));

                                                    when "01" =>
                                                        --  line 1 base address: x40
                                                        BADDR := to_integer(unsigned(COL)) + 64;
                                                    
                                                    when "10" =>
                                                        --  line 2 base address: x14
                                                        BADDR := to_integer(unsigned(COL)) + 20;
                                                    
                                                    when "11" =>
                                                        --  line 3 base address: x54
                                                        BADDR := to_integer(unsigned(COL)) + 84;
                                                end case;
                                                --  compiling the command
                                                data := std_logic_vector(to_unsigned(BADDR, 8));
                                                r_dbg <= to_integer(unsigned(data));
                                                HL_bits := data or x"80";
                                                H_bits := (HL_bits(7 downto 4)&"0000");
                                                L_bits := (HL_bits(3 downto 0)&"0000");
                                                -- se cosi non va, provo ad invertire scrivendo: (H_bits | x08) & 0xfb e vedere se cosi invece va.
                                                lcd_command(0) <= H_bits or x"08";
                                                lcd_command(1) <= (H_bits or x"04") or x"08";
                                                lcd_command(2) <= (H_bits and x"fb") or x"08";
                                                lcd_command(3) <= L_bits or x"08";
                                                lcd_command(4) <= (L_bits or x"04") or x"08";
                                                lcd_command(5) <= (L_bits and x"fb") or x"08";
                                                --  executing
                                                pc := 0;
                                                pc_lim := 6;
                                                delay := 4000;
                                                r_jump <= s_CMDEXEC_0;
                                                r_stage <= s_INITDEV_0;
                                            --
                                            when 8 =>
                                                --  move cursor left by N col
                                                data := ss_bus_out_data;
                                                --  now to see the COL
                                                a := to_integer(unsigned(data));
                                                b := to_integer(unsigned(COL));
                                                if (a > b) then
                                                    --  in this case, we want to move left by an amount that is greater than the actual physical space
                                                    --  so we set COL to 0
                                                    COL := std_logic_vector(to_unsigned(0, 5));
                                                else
                                                    --  in this way, we set col to the difference
                                                    COL := std_logic_vector(to_unsigned(b - a, 5));
                                                end if;
                                                case (ROW) is
                                                    when "00" =>
                                                        --  line 0 base address: x00
                                                        BADDR := to_integer(unsigned(COL));

                                                    when "01" =>
                                                        --  line 1 base address: x40
                                                        BADDR := to_integer(unsigned(COL)) + 64;
                                                    
                                                    when "10" =>
                                                        --  line 2 base address: x14
                                                        BADDR := to_integer(unsigned(COL)) + 20;
                                                    
                                                    when "11" =>
                                                        --  line 3 base address: x54
                                                        BADDR := to_integer(unsigned(COL)) + 84;
                                                end case;
                                                --  compiling the command
                                                data := std_logic_vector(to_unsigned(BADDR, 8));
                                                r_dbg <= to_integer(unsigned(data));
                                                HL_bits := data or x"80";
                                                H_bits := (HL_bits(7 downto 4)&"0000");
                                                L_bits := (HL_bits(3 downto 0)&"0000");
                                                -- se cosi non va, provo ad invertire scrivendo: (H_bits | x08) & 0xfb e vedere se cosi invece va.
                                                lcd_command(0) <= H_bits or x"08";
                                                lcd_command(1) <= (H_bits or x"04") or x"08";
                                                lcd_command(2) <= (H_bits and x"fb") or x"08";
                                                lcd_command(3) <= L_bits or x"08";
                                                lcd_command(4) <= (L_bits or x"04") or x"08";
                                                lcd_command(5) <= (L_bits and x"fb") or x"08";
                                                --  executing
                                                pc := 0;
                                                pc_lim := 6;
                                                delay := 4000;
                                                r_jump <= s_CMDEXEC_0;
                                                r_stage <= s_INITDEV_0;
                                            --
                                            when 9 =>
                                                --  move cursor right by one col
                                                data := ss_bus_out_data;
                                                --  now to see the COL
                                                a := to_integer(unsigned(data));
                                                b := to_integer(unsigned(COL));
                                                if ((a+b)>19) then
                                                    --  in this case, we want to move right by an amount that is greater than the actual physical space
                                                    --  so we set COL to 19
                                                    COL := std_logic_vector(to_unsigned(19, 5));
                                                else
                                                    --  in this way, we set col to the difference
                                                    COL := std_logic_vector(to_unsigned(a + b, 5));
                                                end if;
                                                case (ROW) is
                                                    when "00" =>
                                                        --  line 0 base address: x00
                                                        BADDR := to_integer(unsigned(COL));

                                                    when "01" =>
                                                        --  line 1 base address: x40
                                                        BADDR := to_integer(unsigned(COL)) + 64;
                                                    
                                                    when "10" =>
                                                        --  line 2 base address: x14
                                                        BADDR := to_integer(unsigned(COL)) + 20;
                                                    
                                                    when "11" =>
                                                        --  line 3 base address: x54
                                                        BADDR := to_integer(unsigned(COL)) + 84;
                                                end case;
                                                --  compiling the command
                                                data := std_logic_vector(to_unsigned(BADDR, 8));
                                                r_dbg <= to_integer(unsigned(data));
                                                HL_bits := data or x"80";
                                                H_bits := (HL_bits(7 downto 4)&"0000");
                                                L_bits := (HL_bits(3 downto 0)&"0000");
                                                -- se cosi non va, provo ad invertire scrivendo: (H_bits | x08) & 0xfb e vedere se cosi invece va.
                                                lcd_command(0) <= H_bits or x"08";
                                                lcd_command(1) <= (H_bits or x"04") or x"08";
                                                lcd_command(2) <= (H_bits and x"fb") or x"08";
                                                lcd_command(3) <= L_bits or x"08";
                                                lcd_command(4) <= (L_bits or x"04") or x"08";
                                                lcd_command(5) <= (L_bits and x"fb") or x"08";
                                                --  executing
                                                pc := 0;
                                                pc_lim := 6;
                                                delay := 4000;
                                                r_jump <= s_CMDEXEC_0;
                                                r_stage <= s_INITDEV_0;
                                            --
                                            when others =>
                                                r_stage <= s_IDLE;
                                        end case;
                                    else
                                        --  otherwise we discard this sort of command
                                        delay := 0;
                                        r_stage <= s_CMDEXEC_0;
                                    end if;
                                
                                when s_REG =>
                                    if (ss_bus_chg='0') then
                                        r_bus_in_latch <= '0';
                                        r_stage <= s_IDLE;
                                    else
                                        r_bus_in_latch <= '1';
                                        r_stage <= s_REG;
                                    end if;
                                
                                when s_CMDEXEC_0 =>
                                    --  releasing the main bus
                                    if (ss_bus_out_drdy='0') then
                                        r_bus_in_latch <= '0';
                                        c_delay := 0;
                                        r_stage <= s_CMDEXEC_1;
                                    else
                                        r_bus_in_latch <= '1';
                                        r_stage <= s_CMDEXEC_0;
                                    end if;
                                
                                when s_CMDEXEC_1 =>
                                    if (c_delay=(delay-1)) then
                                        c_delay := 0;
                                        r_stage <= s_IDLE;
                                    else
                                        c_delay := c_delay + 1;
                                        r_stage <= s_CMDEXEC_1;
                                    end if;
                                
                                when s_CMDEXEC_2 =>
                                    if (c_delay=(200000-1)) then
                                        c_delay := 0;
                                        r_stage <= s_INITDEV_2;
                                    else
                                        c_delay := c_delay + 1;
                                        r_stage <= s_CMDEXEC_2;
                                    end if;

                                when others =>
                                    r_stage <= s_IDLE;
                            end case;
                        end if;
                    end if;
                end process MAIN;

    dbg_stage <= r_dbg;
end Behavioral;

--  sequenza di inizializzazione del display:
--  0x38, 0x38, 0x38
--  ciascuno di questi viene scritto e pulsato, quindi sono 3 byte ciascuna:
--  0x38, 0x34, 0x30
--  0x38, 0x34, 0x30
--  0x38, 0x34, 0x30
--  a questo punto setto interfaccia a 4 bit
--  0x28, 0x24, 0x20
--  imposto carattere & stuff : 0x28 -> 0x20 e 0x08 -> 0x20 e 0x80
--  0x28, 0x24, 0x20
--  0x88, 0x84, 0x80
--  display control: 0x0f -> 0x00 e 0x0f -> 0x00 e 0xf0
--  0x08, 0x04, 0x00
--  0xf8, 0xf4, 0xf0
--  clear: 0x01 --> 0x00 e 0x10
--  0x08, 0x04, 0x00
--  0x18, 0x14, 0x10
--  entry mode: 0x04 | 0x02 | 0x00 -> 0x06 --> 0x00 e 0x60
--  0x08, 0x04, 0x00
--  0x68, 0x64, 0x60
--  home: 0x02 -> 0x00, 0x20
--  0x08, 0x04, 0x00
--  0x28, 0x24, 0x20
--  sequenza finale:


  
