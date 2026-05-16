library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

--  this subdev belongs to the 'I2C subsystem' and it drives the i2c eeprom.
entity subdev_I2C_dev0 is
    generic (
        --  bus topology
        bus_width: integer := 32;
        data_width: integer := 8;
        addr_width: integer := 23;
        --  hardware id for the UART
        --  this allows for data-packets sent from the uart device to reach this and not other sub-devs of the uart
        hw_id: integer := 0;
        hw_i2c_addr: std_logic_vector(6 downto 0) := std_logic_vector(to_unsigned(80, 7));
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
        bus_rq: out std_logic;
        bus_grant: in std_logic;
        bus_busy: in std_logic;
        bus_req_sys: out std_logic;         --  this line must be driven high if one of the peripherals wants to acquire the mainbus
        bus_rdy_sys: in std_logic;          --  this line will go high if the system bus has been granted
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
end subdev_I2C_dev0;

architecture Behavioral of subdev_I2C_dev0 is
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
    type t_SM is (s_INIT, s_IDLE, s_REG, s_END, s_VRT_0, s_VRT_1, s_VRT_2, s_VRT_3, s_VRT_4, s_VRT_5, s_VRT_6, s_VRT_7);
    signal r_stage: t_SM := s_INIT;
    
    --  data components for the eeprom
    signal i2c_cmd_addr: std_logic_vector(7 downto 0);
    signal i2c_devreg: std_logic_vector(15 downto 0);
    
    --  prova
    type BUF_ARRAY is array (0 to 5) of std_logic_vector (7 downto 0);
    signal i2c_packet: BUF_ARRAY := (x"00",x"00",x"00",x"00",x"00",x"00");
begin
    --  shared lines drivers for hardware driver
    HWBUS_DATA_DRV: entity work.buffer_nbits(Behavioral) generic map (w => 8) port map(d => r_hw_bus_data_to, q => hw_data_to, oe=>r_hw_bus_dir);
    HWBUS_KEEP_DRV: entity work.buffer_nbits(Behavioral) generic map (w => 1) port map(d(0) => r_hw_bus_keep, q(0) => hw_keep, oe=>r_hw_bus_dir);
    HWBUS_LATCH_DRV:entity work.buffer_nbits(Behavioral) generic map (w => 1) port map(d(0) => r_hw_bus_latch, q(0) => hw_latch, oe=>r_hw_bus_dir);
    HWBUS_ACK_DRV:  entity work.buffer_nbits(Behavioral) generic map (w => 1) port map(d(0) => r_hw_bus_ack, q(0) => hw_ack, oe=>r_hw_bus_dir);

    --  continuous assignment
    hw_bus_rq <= r_hw_bus_rq;

    --  subbus to interface with the central system
    SBUSINT:    entity work.subbus_dev(Behavioral)
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
                    bus_rq => bus_rq,
                    bus_grant => bus_grant,
                    bus_busy => bus_busy,
                    --  addendum for the sub-dev
                    bus_req_sys => bus_req_sys,
                    bus_rdy_sys => bus_rdy_sys,
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
                    if (falling_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                ss_bus_chg <= '0';
                                ss_bus_out_drdy <= '0';
                                
                            when s_IDLE =>
                                ss_bus_chg <= s_bus_chg;
                                ss_bus_out_drdy <= s_bus_out_drdy;
                                ss_bus_out_done <= s_bus_out_done;
                            
                            when s_REG =>
                                ss_bus_chg <= s_bus_chg;
                                
                            when s_END =>
                                ss_bus_out_drdy <= s_bus_out_drdy;
                            
                            when s_VRT_0 =>
                                ss_hw_bus_grant <= hw_bus_grant;
                            
                            when s_VRT_2 =>
                                ss_hw_drdy <= hw_drdy;
                                ss_hw_done <= hw_done;
                            
                            when s_VRT_3 =>
                                ss_hw_drdy <= hw_drdy;
                            
                            when s_VRT_4 =>
                                ss_bus_out_drdy <= s_bus_out_drdy;
                                ss_bus_out_done <= s_bus_out_done;
                            
                            when s_VRT_5 =>
                                ss_hw_bus_grant <= hw_bus_grant;
                            
                            when s_VRT_6 =>
                                ss_bus_out_drdy <= s_bus_out_drdy;
                                ss_bus_out_done <= s_bus_out_done;
                            
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
                    variable pc_lim: natural := 0;
                    variable nt: natural := 0;
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
                                    pc_lim := 0;
                                    --  going
                                    r_stage <= s_IDLE;
                                
                                when s_IDLE =>
                                    --  in the case of i2c, i just need to listen for local registers or virtual events (the hardware bus is NEVER driven by i2c devices unless first initiated here)
                                    cond := (ss_bus_chg & ss_bus_out_drdy);
                                    r_dbg <= 0;
                                    case (cond) is
                                        when "01" =>
                                            --  virtual event
                                            addr := to_integer(unsigned(s_bus_out_addr)) - 64;
                                            --  checking if it is to setup a multiple read/write command (eeprom page read/write in a single go)
                                            if (addr=32768) then
                                                nt := to_integer(unsigned(s_bus_out_data));
                                                r_stage <= s_END;
                                            else
                                                r_stage <= s_VRT_0;
                                            end if;
                                        
                                        when "10" =>
                                            --  local event
                                            r_stage <= s_REG;
                                        
                                        when others =>
                                            --  nothing
                                            r_stage <= s_IDLE;
                                    end case;
                                
                                when s_REG =>
                                    r_dbg <= 1;
                                    if (ss_bus_chg='0') then
                                        r_bus_in_latch <= '0';
                                        r_stage <= s_IDLE;
                                    else
                                        r_bus_in_latch <= '1';
                                        r_stage <= s_REG;
                                    end if;
                                
                                when s_END =>
                                    r_dbg <= 2;
                                    if (ss_bus_out_drdy='0') then
                                        r_bus_in_latch <= '0';
                                        r_stage <= s_IDLE;
                                    else
                                        r_bus_in_latch <= '1';
                                        r_stage <= s_END;
                                    end if;

                                when s_VRT_0 =>
                                    r_dbg <= 3;
                                    --  requesting the bus
                                    if (ss_hw_bus_grant='1') then
                                        --  bus has been granted
                                        r_hw_bus_data_to <= (others=>'0');
                                        r_hw_bus_keep <= '0';
                                        r_hw_bus_latch <= '0';
                                        r_hw_bus_ack <= '0';
                                        r_hw_bus_dir <= '1';
                                        r_stage <= s_VRT_1;
                                    else
                                        --  bus request
                                        r_hw_bus_rq <= '1';
                                        r_stage <= s_VRT_0;
                                    end if;
                                
                                when s_VRT_1 =>
                                    r_dbg <= 4;
                                    --  we need to read/write to/from thee eeprom
                                    pc := 0;
                                    pc_lim := 6;
                                    addr_bits := std_logic_vector(to_unsigned(addr, 16));
                                    i2c_packet(0)(7) <= s_bus_out_cmd;                      --  i2c command
                                    i2c_packet(0)(6 downto 0) <= hw_i2c_addr;               --  i2c address
                                    i2c_packet(1) <= std_logic_vector(to_unsigned(2, 8));   --  i2c number of bytes to specify the register
                                    i2c_packet(2) <= std_logic_vector(to_unsigned(nt, 8));  --  i2c number of transactions
                                    i2c_packet(3) <= addr_bits(7 downto 0);                 --  lower byte of the 16 bit memory address
                                    i2c_packet(4) <= addr_bits(15 downto 8);                --  upper byte of the 16 bit memory address
                                    i2c_packet(5) <= s_bus_out_data;                        --  data
                                    --  we're ready to go
                                    r_stage <= s_VRT_2;
                                
                                when s_VRT_2 =>
                                    r_dbg <= 5;
                                    if (ss_hw_drdy='1') then
                                        r_bus_in_data <= hw_data_from;
                                        r_hw_bus_latch <= '0';
                                        r_stage <= s_VRT_3;
                                    else
                                        r_hw_bus_data_to <= i2c_packet(pc);
                                        r_hw_bus_latch <= '1';
                                        r_stage <= s_VRT_2;
                                    end if;
                                
                                when s_VRT_3 =>
                                    r_dbg <= 6;
                                    if (ss_hw_drdy='0') then
                                        if (pc=(pc_lim-1)) then
                                            r_stage <= s_VRT_4;
                                        else
                                            pc := pc + 1;
                                            r_stage <= s_VRT_2;
                                        end if;
                                    else
                                        --  waiting
                                        r_stage <= s_VRT_3;
                                    end if;
                                
                                when s_VRT_4 =>
                                    r_dbg <= 7;
                                    if (ss_bus_out_drdy='0') then
                                        --  it has transmitted/received data
                                        r_bus_in_latch <= '0';  
                                        if (ss_hw_done='1') then
                                            --  no more transactions to/from the i2c driver
                                            --  checking if the bus is done too
                                            if (ss_bus_out_done='1') then
                                                --  done here also, so
                                                r_stage <= s_VRT_5;
                                            else
                                                --  maintaing ownership of the hardware bus
                                                r_stage <= s_IDLE;
                                            end if;
                                        else
                                            --  we still have more things to do with the i2c
                                            r_stage <= s_VRT_6;
                                        end if;
                                    else
                                        --  launching
                                        r_bus_in_latch <= '1';
                                        r_stage <= s_VRT_4;
                                    end if;
                                
                                when s_VRT_5 =>
                                    r_dbg <= 8;
                                    if (ss_hw_bus_grant='0') then
                                        --  all done
                                        nt := 1;
                                        r_stage <= s_IDLE;
                                    else
                                        --  bus release
                                        r_hw_bus_dir <= '0';
                                        r_hw_bus_rq <= '0';
                                        r_stage <= s_VRT_5;
                                    end if;
                                
                                when s_VRT_6 =>
                                    if (ss_bus_out_drdy='1') then
                                        i2c_packet(5) <= s_bus_out_data;
                                        r_stage <= s_VRT_2;
                                    else
                                        r_stage <= s_VRT_6;
                                    end if;
                                                                                                
                                when others =>
                                    r_stage <= s_IDLE;
                            end case;
                        end if;
                    end if;
                end process MAIN;

    dbg_stage <= r_dbg;
end Behavioral;
