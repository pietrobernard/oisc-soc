library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity dev_v2 is
    generic (
        --  bus topology
        bus_width: integer := 32;
        data_width: integer := 8;
        addr_width: integer := 23;
        --  device data
        dev_id: integer := 0;
        --  device memory range
        --  these addresses must be >= 0x20000
        dev_mem_begin: integer := 0;    --  start of memory address space
        dev_mem_end: integer := 0;      --  end of memory address space
        --  sram reserved memory
        --  this memory lies outside of the above mentioned space
        dev_phy_begin: integer := 0;    --  start of sram range
        dev_phy_end: integer := 0;      --  end of sram range
        --  register file configuration
        regcfg: string := "generic.mem" --  register file configuration memfile
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  bus interface signals
        bus_lines: inout std_logic_vector(bus_width-1 downto 0);
        bus_strobe_M: inout std_logic;
        bus_strobe_S: inout std_logic;
        bus_keep: inout std_logic;
        bus_done_S: inout std_logic;
        bus_rq: out std_logic;
        bus_grant: in std_logic;
        bus_busy: in std_logic;
        --  external interface signals
        dev_in_cmd: in std_logic;
        dev_in_addr: in std_logic_vector(addr_width-1 downto 0);
        dev_in_data: in std_logic_vector(data_width-1 downto 0);
        dev_in_latch: in std_logic;
        dev_in_keep: in std_logic;
        dev_out_cmd: out std_logic;
        dev_out_addr: out std_logic_vector(addr_width-1 downto 0);
        dev_out_data: out std_logic_vector(data_width-1 downto 0);
        dev_out_drdy: out std_logic;
        dev_out_done: out std_logic;
        dev_err: out std_logic;
        dev_chg: out std_logic;
        --  debug ports
        dbg_stage: out natural;
        dbg_reg_drdy: out std_logic;
        dbg_reg_done: out std_logic;
        dbg_bus_drdy: out std_logic;
        devbus_interface: out natural;
        --  debug busmode
        dbg_busmode: out std_logic_vector(1 downto 0)
    );
end dev_v2;

architecture Behavioral of dev_v2 is
    --  some constants
    --  every device has 32 base registers (8 bit wide) + up to 32 logical registers (sub/combinations of base registers)
    --  by design, registers 0 to 31 are base registers while 32 to 63 are logical
    constant dev_reg_begin: integer := dev_mem_begin;
    constant dev_reg_end: integer := (dev_mem_begin+63);
    --  virtual addresses cover the remaining part of the memory space from dev_mem_begin+64 to dev_mem_end
    --  virtual addresses are specified in the device customization phase
    constant dev_vrt_begin: integer := (dev_mem_begin+64);
    constant dev_vrt_end: integer := dev_mem_end;
    
    --  EXT INTERFACE SIGNALS
    --  sampling signals
    signal s_dev_in_cmd: std_logic := '0';
    signal s_dev_in_addr: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal s_dev_in_data: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal s_dev_in_latch: std_logic := '0';
    signal s_dev_in_keep: std_logic := '0';
        
    --  driving signals
    signal r_dev_out_cmd: std_logic := '0';
    signal r_dev_out_addr: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal r_dev_out_data: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal r_dev_out_drdy: std_logic := '0';
    signal r_dev_out_done: std_logic := '0';
    signal r_dev_err: std_logic := '0';
    signal r_dev_chg: std_logic := '0';
                
    --  BUS INTERFACE SIGNALS
    --  sampling signals
    signal s_bus_command_from: std_logic := '0';
    signal s_bus_address_from: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal s_bus_data_from: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal s_bus_drdy: std_logic := '0';
    signal s_bus_done: std_logic := '0';
    signal ss_bus_command_from: std_logic := '0';   
    signal ss_bus_address_from: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal ss_bus_data_from: std_logic_vector(data_width-1 downto 0) := (others=>'0'); 
    signal ss_bus_drdy: std_logic := '0';
    signal ss_bus_done: std_logic := '0';
    signal ss_bus_ready: std_logic := '0';
    signal ss_bus_busy: std_logic := '0';
    signal s_bus_booked: std_logic;
    --signal ss_bus_booked: std_logic := '0';
    signal s_bus_rq_error: std_logic;
    signal ss_bus_rq_error: std_logic := '0';
    signal s_bus_mode: std_logic_vector(1 downto 0);
    signal ss_bus_mode: std_logic_vector(1 downto 0) := "00";
    
    --  synchronizers
    signal ss_sync_0: std_logic := '0';
    signal ss_sync_1: std_logic := '0';
    
    --  driving signals
    signal r_bus_command_to: std_logic := '0';
    signal r_bus_address_to: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal r_bus_data_to: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal r_bus_latch: std_logic := '0';
    --signal r_bus_ack: std_logic := '0';
    signal r_bus_keep: std_logic := '0';
    signal r_bus_book: std_logic := '0';
    signal r_bus_clear: std_logic := '0';
    
    --  REGISTER FILE SIGNALS
    --  sampling signals
    signal s_reg_data_fr: std_logic_vector(data_width-1 downto 0) := (others=>'0');    
    signal s_reg_drdy: std_logic := '0';
    signal s_reg_done: std_logic := '0';        
    signal ss_reg_drdy: std_logic := '0';
    signal ss_reg_done: std_logic := '0';
    signal ss_reg_data_fr: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    
    --  driving signals
    signal r_reg_data_to: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal r_reg_address: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal r_reg_cmd: std_logic := '0';
    signal r_reg_latch: std_logic := '0';
    
    --  STATE MACHINE
    type t_SM is (  s_INIT, s_IDLE, s_LATCH_ERR, s_ADDR_CHECK_INT, s_ADDR_CHECK_BUS, s_WAIT,
                    s_M_0, s_M_1, s_M_2, s_M_3, s_M_4, s_M_5,
                    s_R_asM_0, s_R_asM_1, s_R_asM_2, s_R_asM_3,
                    s_R_asS_0, s_R_asS_1, s_R_asS_2, s_R_asS_2b, s_R_asS_2c, s_R_asS_3,
                    s_VRT_0, s_VRT_1, s_VRT_2, s_VRT_3
                 );
    signal r_stage: t_SM := s_INIT;
    signal r_jump: t_SM := s_INIT;
    
    signal r_dbg_stage: natural := 0;
begin
    --  interface to the system bus
    DEV_BUS_INT:    entity work.bus_interface_v2(Behavioral)
                        generic map (
                            bus_width => bus_width,
                            data_width => data_width,
                            addr_width => addr_width,
                            dev_mem_begin => dev_mem_begin,
                            dev_mem_end => dev_mem_end,
                            dev_id => dev_id                            
                        ) port map (
                            sysClk => sysClk,
                            sysRstb => sysRstb,
                            --  bus lines and logic
                            bus_lines => bus_lines,
                            bus_strobe_M => bus_strobe_M,
                            bus_strobe_S => bus_strobe_S,
                            bus_keep => bus_keep,
                            bus_done_S => bus_done_S,
                            --  bus arbiter
                            bus_rq => bus_rq,
                            bus_grant => bus_grant,
                            bus_busy => bus_busy,
                            --  interface addr/data
                            command_to => r_bus_command_to,
                            command_from => s_bus_command_from,
                            address_to => r_bus_address_to,
                            address_from => s_bus_address_from,
                            data_to => r_bus_data_to,
                            data_from => s_bus_data_from,
                            --  interface sync
                            latch => r_bus_latch,
                            done => s_bus_done,
                            drdy => s_bus_drdy,
                            keep => r_bus_keep,
                            book => r_bus_book,
                            booked => s_bus_booked,
                            rq_error => s_bus_rq_error,
                            interface_mode => s_bus_mode,
                            clear => r_bus_clear,
                            --  debug
                            dbg_stage => devbus_interface
                        );

    --  register file
    REG_FILE_INT:   entity work.regs(Behavioral)
                        generic map (
                            memfile => regcfg
                        ) port map (
                            sysClk => sysClk,
                            sysRstb => sysRstb,
                            --  stuff
                            r_cmd => r_reg_cmd,
                            r_address => r_reg_address,
                            r_data_to => r_reg_data_to,
                            r_data_fr => s_reg_data_fr,
                            latch_cmd => r_reg_latch,
                            drdy => s_reg_drdy,
                            done => s_reg_done
                        );

    --  sampler
    SAMPLER:    process (sysClk)
    
                begin
                    if (rising_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                --  initialization stage
                                ss_bus_command_from <= '0';
                                ss_bus_drdy <= '0';
                                ss_bus_done <= '0';
                                --ss_bus_booked <= '0';
                                ss_bus_rq_error <= '0';
                                ss_bus_mode <= (others=>'0');
                                --  sync
                                ss_sync_0 <= '0';
                                ss_sync_1 <= '0';
                                --  reg
                                ss_reg_drdy <= '0';
                                ss_reg_done <= '0';
                                --  ext interface
                                s_dev_in_cmd <= '0';
                                s_dev_in_addr <= (others=>'0');
                                s_dev_in_data <= (others=>'0');
                                s_dev_in_latch <= '0';
                                s_dev_in_keep <= '0';
                            
                            when s_IDLE =>
                                --  sampling the bus
                                ss_bus_drdy <= s_bus_drdy;
                                ss_bus_command_from <= s_bus_command_from;
                                ss_bus_data_from <= s_bus_data_from;
                                ss_bus_address_from <= s_bus_address_from;
                                ss_bus_done <= s_bus_done;
                                --  sampling the interface                                
                                s_dev_in_latch <= dev_in_latch;
                                s_dev_in_cmd <= dev_in_cmd;
                                s_dev_in_data <= dev_in_data;
                                s_dev_in_addr <= dev_in_addr;
                                s_dev_in_keep <= dev_in_keep;
                                --  syncs
                                ss_sync_0 <= '0';
                                ss_sync_1 <= '0';
                            
                            when s_LATCH_ERR =>
                                s_dev_in_latch <= dev_in_latch;
                            
                            when s_ADDR_CHECK_BUS =>
                                ss_sync_0 <= '0';
                            
                            when s_R_asM_0 =>
                                s_dev_in_latch <= dev_in_latch;
                                s_dev_in_addr <= dev_in_addr;
                                s_dev_in_cmd <= dev_in_cmd;
                                s_dev_in_data <= dev_in_data;
                                s_dev_in_keep <= dev_in_keep;
                            
                            when s_R_asM_1 =>
                                ss_reg_drdy <= s_reg_drdy;
                                ss_reg_done <= s_reg_done;
                                ss_reg_data_fr <= s_reg_data_fr;
                            
                            when s_R_asM_2 =>
                                ss_reg_drdy <= s_reg_drdy;
                            
                            when s_R_asM_3 =>
                                s_dev_in_latch <= dev_in_latch;
                            
                            when s_R_asS_0 =>
                                ss_bus_drdy <= s_bus_drdy;
                                ss_bus_command_from <= s_bus_command_from;
                                ss_bus_data_from <= s_bus_data_from;
                                ss_bus_address_from <= s_bus_address_from;
                                ss_bus_done <= s_bus_done;
                            
                            when s_R_asS_1 =>
                                ss_reg_drdy <= s_reg_drdy;
                                ss_reg_done <= s_reg_done;
                                ss_reg_data_fr <= s_reg_data_fr;
                            
                            when s_R_asS_2 =>
                                ss_reg_drdy <= s_reg_drdy;
                            
                            when s_R_asS_2b =>
                                s_dev_in_latch <= dev_in_latch;
                            
                            when s_R_asS_2c =>
                                s_dev_in_latch <= dev_in_latch;
                            
                            when s_R_asS_3 =>
                                ss_bus_drdy <= s_bus_drdy;
                                --  init
                                ss_bus_mode <= s_bus_mode;
                            
                            when s_VRT_0 =>
                                ss_bus_drdy <= s_bus_drdy;
                                ss_bus_command_from <= s_bus_command_from;
                                ss_bus_data_from <= s_bus_data_from;
                                ss_bus_address_from <= s_bus_address_from;
                                ss_bus_done <= s_bus_done;
                                ss_sync_0 <= '1';
                            
                            when s_VRT_1 =>
                                s_dev_in_latch <= dev_in_latch;
                                s_dev_in_data <= dev_in_data;
                                s_dev_in_keep <= dev_in_keep;
                                ss_sync_0 <= '0';
                            
                            when s_VRT_2 =>
                                s_dev_in_latch <= dev_in_latch;
                            
                            when s_VRT_3 =>
                                ss_bus_drdy <= s_bus_drdy;
                                --  init
                                ss_bus_mode <= s_bus_mode;
                            
                            when s_M_0 =>
                                s_dev_in_latch <= dev_in_latch;
                                s_dev_in_cmd <= dev_in_cmd;
                                s_dev_in_data <= dev_in_data;
                                s_dev_in_addr <= dev_in_addr;
                                s_dev_in_keep <= dev_in_keep;
                                ss_sync_1 <= '1';
                                --  init
                                ss_bus_mode <= s_bus_mode;
                                ss_bus_rq_error <= '0';
                            
                            when s_M_1 =>
                                ss_bus_mode <= s_bus_mode;
                                ss_bus_rq_error <= s_bus_rq_error;
                                ss_sync_0 <= '1';
                                ss_sync_1 <= '0';
                            
                            when s_M_2 =>
                                ss_bus_rq_error <= s_bus_rq_error;
                                ss_sync_0 <= '0';
                            
                            when s_M_3 =>
                                ss_sync_0 <= '0';
                                ss_bus_drdy <= s_bus_drdy;
                                ss_bus_command_from <= s_bus_command_from;
                                ss_bus_data_from <= s_bus_data_from;
                                ss_bus_address_from <= s_bus_address_from;
                                ss_bus_done <= s_bus_done;
                            
                            when s_M_4 =>
                                s_dev_in_latch <= dev_in_latch;
                            
                            when s_M_5 =>
                                ss_bus_drdy <= s_bus_drdy;
                                --  init
                                ss_bus_mode <= s_bus_mode;
                            
                            when s_WAIT =>
                                ss_bus_mode <= s_bus_mode;
                                ss_bus_drdy <= s_bus_drdy;
                                ss_sync_0 <= '1';
                                                            
                            when others =>
                                null;
                        end case;
                    end if;
                end process SAMPLER;

    MAIN:       process (sysClk)
                    variable cond: std_logic_vector(1 downto 0) := "00";
                    variable check: std_logic_vector(2 downto 0) := "000";
                    variable check4: std_logic_vector(3 downto 0) := "0000";
                    variable addr: natural := 0;
                    variable addr_reduced: natural := 0;
                    variable flavour: std_logic := '0';
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            --  reset
                            r_stage <= s_INIT;
                        else
                            --  case
                            case (r_stage) is
                                when s_INIT =>
                                    --  debug
                                    r_dbg_stage <= 0;
                                    --  ext
                                    r_dev_out_cmd <= '0';
                                    r_dev_out_addr <= (others=>'0');
                                    r_dev_out_data <= (others=>'0');
                                    r_dev_out_drdy <= '0';
                                    r_dev_out_done <= '0';
                                    r_dev_err <= '0';
                                    --  bus
                                    r_bus_command_to <= '0';
                                    r_bus_address_to <= (others=>'0');
                                    r_bus_data_to <= (others=>'0');
                                    r_bus_latch <= '0';
                                    --r_bus_ack <= '0';
                                    r_bus_keep <= '0';
                                    r_bus_book <= '0';
                                    r_bus_clear <= '0';
                                    --  reg
                                    r_reg_data_to <= (others=>'0');
                                    r_reg_address <= (others=>'0');
                                    r_reg_cmd <= '0';
                                    r_reg_latch <= '0';
                                    --  going
                                    r_stage <= s_IDLE;
                                
                                when s_IDLE =>
                                    --  here we must wait for events:
                                    r_dbg_stage <= 1;
                                    cond := (ss_bus_drdy & s_dev_in_latch);
                                    case (cond) is
                                        when "00" =>
                                            --  the bus is idle and no events occurr from the interface
                                            r_dev_err <= '0';
                                            r_stage <= s_IDLE;
                                        
                                        when "01" =>
                                            --  the interface is requesting to drive the request to drive the bus
                                            --  or the local registers.
                                            r_stage <= s_ADDR_CHECK_INT;
                                        
                                        when "10" =>
                                            --  event from the bus
                                            r_stage <= s_ADDR_CHECK_BUS;
                                        
                                        when "11" =>
                                            --  concurrency -> must first release the drive attempt
                                            r_stage <= s_LATCH_ERR;
                                    end case;
                                
                                when s_LATCH_ERR =>
                                    r_dbg_stage <= 2;
                                    if (s_dev_in_latch='0') then
                                        r_dev_err <= '0';
                                        r_stage <= s_IDLE;
                                    else
                                        r_dev_err <= '1';
                                        r_stage <= s_LATCH_ERR;
                                    end if;
                                
                                when s_ADDR_CHECK_INT =>
                                    r_dbg_stage <= 3;
                                    addr := to_integer(unsigned(s_dev_in_addr));
                                    if ((addr >= dev_reg_begin) and (addr <= dev_reg_end)) then
                                        --  this event must be forwarded to the physical register handler
                                        r_stage <= s_R_asM_0;
                                    else
                                        --  this event is for the outside world
                                        r_stage <= s_M_0;
                                    end if;
                                
                                when s_ADDR_CHECK_BUS =>
                                    r_dbg_stage <= 4;
                                    addr := to_integer(unsigned(ss_bus_address_from));
                                    if ((addr >= dev_reg_begin) and (addr <= dev_reg_end)) then
                                        --  this event must be forwarded to the physical register handler
                                        r_stage <= s_R_asS_0;
                                    else
                                        --  this event must be forwarded to the virtual register handler
                                        r_stage <= s_VRT_0;
                                    end if;
                                
                                --  LOCAL REGISTER HANDLING (AS MASTER)
                                --  In this case, the local interface is handling the local register, so the device acts on itself
                                --  and no bus booking or action is necessary since it does everything here.
                                when s_R_asM_0 =>
                                    r_dbg_stage <= 5;
                                    addr_reduced := to_integer(unsigned(s_dev_in_addr)) - dev_reg_begin;
                                    if (s_dev_in_latch='1') then
                                        --  data for register controller
                                        r_reg_cmd <= s_dev_in_cmd;
                                        r_reg_address <= std_logic_vector(to_unsigned(addr_reduced, data_width));
                                        r_reg_data_to <= s_dev_in_data;
                                        --  going
                                        r_stage <= s_R_asM_1;
                                    else
                                        --  waiting
                                        r_stage <= s_R_asM_0;
                                    end if;
                                
                                when s_R_asM_1 =>
                                    r_dbg_stage <= 6;
                                    if (ss_reg_drdy='1') then
                                        --  we've done the thing, so:
                                        r_dev_out_cmd <= r_reg_cmd;
                                        r_dev_out_addr <= std_logic_vector(to_unsigned(addr_reduced + dev_reg_begin, addr_width));
                                        r_dev_out_data <= ss_reg_data_fr;
                                        r_dev_out_done <= ss_reg_done;
                                        --  display later
                                        r_stage <= s_R_asM_2;
                                    else
                                        --  we now wait for the register system to do its thing
                                        r_reg_latch <= '1';
                                        r_stage <= s_R_asM_1;
                                    end if;
                                
                                when s_R_asM_2 =>
                                    r_dbg_stage <= 7;
                                    if (ss_reg_drdy='0') then
                                        r_stage <= s_R_asM_3;
                                    else
                                        r_reg_latch <= '0';
                                        r_stage <= s_R_asM_2;
                                    end if;
                                
                                when s_R_asM_3 =>
                                    r_dbg_stage <= 8;
                                    if (s_dev_in_latch='0') then
                                        --  done
                                        r_dev_out_drdy <= '0';
                                        cond := (r_dev_out_done & r_dev_out_cmd);
                                        case (cond) is
                                            when "10"|"11" =>
                                                --  we are finished with the registers
                                                r_dev_out_done <= '0';
                                                r_stage <= s_IDLE;
                                        
                                            when "00"|"01" =>
                                                --  we need multiple writes / reads, so:
                                                r_stage <= s_R_asM_0;
                                        end case;
                                    else
                                        --  displaying
                                        r_dev_out_drdy <= '1';
                                        r_stage <= s_R_asM_3;
                                    end if;
                                
                                --  LOCAL REGISTER HANDLING (AS SLAVE)
                                --  In this case, we receive an event from the bus we're attached to and the remote end wants to
                                --  interact with our local registers.
                                when s_R_asS_0 =>
                                    r_dbg_stage <= 9;
                                    addr_reduced := to_integer(unsigned(ss_bus_address_from)) - dev_reg_begin;
                                    if (ss_bus_drdy='1') then
                                        --  data for register controller
                                        r_reg_cmd <= ss_bus_command_from;
                                        r_reg_address <= std_logic_vector(to_unsigned(addr_reduced, data_width));
                                        r_reg_data_to <= ss_bus_data_from;
                                        --  going
                                        r_stage <= s_R_asS_1;
                                    else
                                        --  waiting
                                        r_stage <= s_R_asS_0;
                                    end if;
                                
                                when s_R_asS_1 =>
                                    r_dbg_stage <= 10;
                                    if (ss_reg_drdy='1') then
                                        --  we've done the thing, so:
                                        r_bus_command_to <= r_reg_cmd;
                                        r_bus_address_to <= std_logic_vector(to_unsigned(addr_reduced + dev_reg_begin, addr_width));
                                        r_bus_data_to <= ss_reg_data_fr;
                                        if (r_reg_cmd='0') then
                                            r_bus_keep <= '0';
                                        else
                                            r_bus_keep <= (not ss_reg_done);
                                        end if;
                                        --  display later
                                        r_stage <= s_R_asS_2;
                                    else
                                        --  we now wait for the register system to do its thing
                                        r_reg_latch <= '1';
                                        r_stage <= s_R_asS_1;
                                    end if;
                                
                                when s_R_asS_2 =>
                                    r_dbg_stage <= 11;
                                    if (ss_reg_drdy='0') then
                                        r_stage <= s_R_asS_2b;
                                    else
                                        r_reg_latch <= '0';
                                        r_stage <= s_R_asS_2;
                                    end if;
                                
                                when s_R_asS_2b =>
                                    r_dbg_stage <= 12;
                                    if (s_dev_in_latch='1') then
                                        --  signal delivered
                                        r_stage <= s_R_asS_2c;
                                    else
                                        --  signalling the interface that the register has changed
                                        r_dev_out_cmd <= r_bus_command_to;
                                        r_dev_out_addr <= r_bus_address_to;
                                        r_dev_out_data <= r_bus_data_to;
                                        r_dev_out_done <= (not r_bus_keep);
                                        --  showing
                                        r_dev_chg <= '1';
                                        r_stage <= s_R_asS_2b;
                                    end if;
                                
                                when s_R_asS_2c =>
                                    r_dbg_stage <= 13;
                                    if (s_dev_in_latch='0') then
                                        --  going forward
                                        r_stage <= s_R_asS_3;
                                    else
                                        --  releasing signal
                                        r_dev_out_cmd <= '0';
                                        r_dev_out_addr <= (others=>'0');
                                        r_dev_out_data <= (others=>'0');
                                        r_dev_out_done <= '0';
                                        --  releasing                                        
                                        r_dev_chg <= '0';
                                        r_stage <= s_R_asS_2c;
                                    end if;
                                
                                when s_R_asS_3 =>
                                    r_dbg_stage <= 14;
                                    if (ss_bus_drdy='0') then
                                        --  done
                                        r_bus_latch <= '0';
                                        cond := (r_bus_keep & r_bus_command_to);
                                        case (cond) is
                                            when "00"|"01" =>
                                                --  we are finished, we need to wait for the bus to change
                                                r_stage <= s_WAIT;
                                            
                                            when "10"|"11" =>
                                                --  we need to do multiple read/writes, so
                                                r_stage <= s_R_asS_0;
                                        end case;
                                    else
                                        --  displaying
                                        r_bus_latch <= '1';
                                        r_stage <= s_R_asS_3;
                                    end if;
                                
                                --  VIRTUAL REGISTER HANDLING (AS SLAVE)
                                --  When the input address lies outside of the physical/logical range, the targets are the
                                --  so called virtual registers that are used to encode specific functions of the device or
                                --  also specific storage facilities.
                                when s_VRT_0 =>
                                    r_dbg_stage <= 15;
                                    addr_reduced := to_integer(unsigned(ss_bus_address_from)) - dev_reg_begin;
                                    if ((ss_sync_0='1') and (ss_bus_drdy='1')) then
                                        --  data for the interface
                                        r_dev_out_cmd <= ss_bus_command_from;
                                        r_dev_out_addr <= std_logic_vector(to_unsigned(addr_reduced, addr_width));
                                        r_dev_out_data <= ss_bus_data_from;
                                        r_dev_out_done <= ss_bus_done;
                                        --  going
                                        r_stage <= s_VRT_1;
                                    else
                                        --  waiting
                                        r_stage <= s_VRT_0;
                                    end if;
                                
                                when s_VRT_1 =>
                                    r_dbg_stage <= 16;
                                    if (s_dev_in_latch='1') then
                                        --  we have the response to feed back to the bus
                                        r_bus_command_to <= r_dev_out_cmd;
                                        r_bus_address_to <= std_logic_vector(to_unsigned(addr_reduced + dev_reg_begin, addr_width));
                                        r_bus_data_to <= s_dev_in_data;
                                        r_bus_keep <= s_dev_in_keep;
                                        --  going
                                        r_stage <= s_VRT_2;
                                    else
                                        --  waiting for the interface's response
                                        r_dev_out_drdy <= '1';
                                        r_stage <= s_VRT_1;
                                    end if;
                                
                                when s_VRT_2 =>
                                    r_dbg_stage <= 17;
                                    if (s_dev_in_latch='0') then
                                        r_stage <= s_VRT_3;
                                    else
                                        r_dev_out_drdy <= '0';
                                        r_stage <= s_VRT_2;
                                    end if;
                                
                                when s_VRT_3 =>
                                    r_dbg_stage <= 18;
                                    if (ss_bus_drdy='0') then
                                        r_bus_latch <= '0';
                                        --  checking what to do
                                        cond := (r_bus_keep & (not r_dev_out_done));
                                        case (cond) is
                                            when "00"|"01" =>
                                                --  both the remote master and ourselves have finished
                                                --  or the master could initiate another transaction
                                                r_stage <= s_WAIT;
                                            
                                            when "10"|"11" =>
                                                --  we have more to send the master
                                                r_stage <= s_VRT_0;
                                        end case;
                                    else
                                        --  sending response to the bus
                                        r_bus_latch <= '1';
                                        r_stage <= s_VRT_3;
                                    end if;
                                
                                --  MASTER SECTION
                                --  Here we try to master the bus. We first have to gather some data and try to latch it on.
                                when s_M_0 =>
                                    r_dbg_stage <= 19;
                                    if ((ss_sync_1='1') and (s_dev_in_latch='1')) then
                                        --  here's the data
                                        r_bus_command_to <= s_dev_in_cmd;
                                        r_bus_address_to <= s_dev_in_addr;
                                        r_bus_data_to <= s_dev_in_data;
                                        r_bus_keep <= s_dev_in_keep;
                                        --  going
                                        r_stage <= s_M_1;
                                    else
                                        --  waiting
                                        r_stage <= s_M_0;
                                    end if;
                                                                                                                                                                
                                when s_M_1 =>
                                    r_dbg_stage <= 20;
                                    check4 := ss_sync_0 & ss_bus_mode & ss_bus_rq_error;
                                    case (check4) is
                                        when "1000" =>
                                            --  we wait
                                            r_bus_latch <= '1';
                                            r_stage <= s_M_1;
                                        
                                        when "1010" =>
                                            --  we succesfully obtained master
                                            r_stage <= s_M_3;
                                        
                                        when "1101"|"1111" =>
                                            --  an error occurred and the bus became slave
                                            r_stage <= s_M_2;
                                        
                                        when others =>
                                            --  illegal condition or not ready
                                            r_stage <= s_M_1;
                                    end case;
                                
                                when s_M_2 =>
                                    r_dbg_stage <= 21;
                                    --  termination of request, so
                                    if (ss_bus_rq_error='0') then
                                        r_stage <= s_LATCH_ERR;
                                    else
                                        r_bus_latch <= '0';
                                        r_stage <= s_M_2;
                                    end if;
                                
                                when s_M_3 =>
                                    r_dbg_stage <= 22;
                                    --  we can start with the transaction
                                    addr_reduced := to_integer(unsigned(ss_bus_address_from)) - dev_reg_begin;
                                    if (ss_bus_drdy='1') then
                                        --  here is the slave's response to our command
                                        r_dev_out_cmd <= ss_bus_command_from;
                                        r_dev_out_addr <= std_logic_vector(to_unsigned(addr_reduced, addr_width));
                                        r_dev_out_data <= ss_bus_data_from;
                                        r_dev_out_done <= ss_bus_done;
                                        --  showing
                                        r_stage <= s_M_4;
                                    else
                                        --  waiting for the slave response
                                        r_bus_latch <= '1';
                                        r_stage <= s_M_3;
                                    end if;
                                
                                when s_M_4 =>
                                    r_dbg_stage <= 23;
                                    if (s_dev_in_latch='0') then
                                        --  interface ok
                                        r_dev_out_drdy <= '0';
                                        r_stage <= s_M_5;
                                    else
                                        --  waiting for the interface to ack
                                        r_dev_out_drdy <= '1';
                                        r_stage <= s_M_4;
                                    end if;
                                
                                when s_M_5 =>
                                    r_dbg_stage <= 24;
                                    if (ss_bus_drdy='0') then
                                        --  checking now what to do
                                        cond := (not(r_dev_out_done) & r_bus_keep);
                                        case (cond) is
                                            when "00" =>
                                                --  in this case we are finished
                                                r_stage <= s_WAIT;
                                            
                                            when "01" =>
                                                --  in this case we have more to send
                                                r_stage <= s_M_0;
                                            
                                            when "10"|"11" =>
                                                --  in this case the slave wants to send us more
                                                r_stage <= s_M_3;
                                        end case;
                                    else
                                        --  waiting for remote device
                                        r_bus_latch <= '0';
                                        r_stage <= s_M_5;
                                    end if;
                                
                                --  Wait stage
                                when s_WAIT =>
                                    r_dbg_stage <= 25;
                                    --  shutting off the interface
                                    r_dev_out_cmd <= '0';
                                    r_dev_out_addr <= (others=>'0');
                                    r_dev_out_data <= (others=>'0');
                                    r_dev_out_drdy <= '0';
                                    r_dev_out_done <= '0';
                                    --  waiting
                                    check := ss_sync_0 & ss_bus_mode;
                                    case (check) is
                                        when "100" =>
                                            --  the bus is now inactive
                                            r_stage <= s_IDLE;
                                        
                                        when "110" =>
                                            --  we are still in active mode
                                            if (ss_bus_drdy='1') then
                                                --  it is for us, so let's see if it is for virtual or local registers
                                                r_stage <= s_ADDR_CHECK_BUS;
                                            else
                                                --  we wait here
                                                r_stage <= s_WAIT;
                                            end if;
                                            
                                        when "111" =>
                                            --  we are inactive, so we just wait here
                                            r_stage <= s_WAIT;
                                        
                                        when others =>
                                            r_stage <= s_WAIT;
                                    end case;
                                
                                when others =>
                                    r_stage <= s_IDLE;
                            end case;
                        end if;
                    end if;
                end process MAIN;
    
    --  output assignments
    dbg_stage <= r_dbg_stage;
    dev_out_cmd <= r_dev_out_cmd;
    dev_out_addr <= r_dev_out_addr;
    dev_out_data <= r_dev_out_data;
    dev_out_drdy <= r_dev_out_drdy;
    dev_out_done <= r_dev_out_done;
    dev_err <= r_dev_err;
    dev_chg <= r_dev_chg;
    
    --  debug
    dbg_reg_drdy <= ss_reg_drdy;
    dbg_reg_done <= ss_reg_done;
    dbg_bus_drdy <= ss_bus_drdy;
    
    dbg_busmode <= ss_bus_mode;
                        

end Behavioral;
