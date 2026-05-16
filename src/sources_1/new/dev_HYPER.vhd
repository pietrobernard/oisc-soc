library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

----------------------------------------------------------------------------------------
--
--  HYPERVISOR DEVICE
--
--  The hypervisor is a device that initializes the system on powerup.
--  When each device powers up, it is by default locked in the 'init' stage.
--  Each device must wait for the hypervisor to contact it and start the initi sequence.
--  When a device completes its initialization, it must signal the hypervisor that all
--  has been done and wait. When all devices have been initialized, the hypervisor
--  signals one device after the other that it might start operating.
--
----------------------------------------------------------------------------------------
entity dev_HYPER is
    generic (
        --  bus topology
        bus_width: integer := 32;
        data_width: integer := 8;
        addr_width: integer := 23;
        --  device manager setup
        dev_id: integer := 7;
        dev_mem_begin: integer := 0;    --  start of memory space for the UART device
        dev_mem_end: integer := 0;      --  end of memory space for the UART device 
        --  device addresses
        d0_mem_begin: integer := 0;
        d0_mem_end: integer := 0;
        d1_mem_begin: integer := 0;
        d1_mem_end: integer := 0;
        d2_mem_begin: integer := 0;
        d2_mem_end: integer := 0;
        d3_mem_begin: integer := 0;
        d3_mem_end: integer := 0;
        d4_mem_begin: integer := 0;
        d4_mem_end: integer := 0;
        d5_mem_begin: integer := 0;
        d5_mem_end: integer := 0;
        d6_mem_begin: integer := 0;
        d6_mem_end: integer := 0
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  system bus interface signals
        bus_lines: inout std_logic_vector(bus_width-1 downto 0);
        bus_strobe_M: inout std_logic;
        bus_strobe_S: inout std_logic;
        bus_keep: inout std_logic;
        bus_rq: out std_logic;
        bus_grant: in std_logic;
        bus_busy: in std_logic
    );
end dev_HYPER;

architecture Behavioral of dev_HYPER is
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
    signal ss_dev_out_addr: std_logic_vector(addr_width-1 downto 0);
    signal ss_dev_out_data: std_logic_vector(data_width-1 downto 0);
    signal ss_dev_out_drdy: std_logic;
    signal ss_dev_out_done: std_logic;
    signal ss_dev_err: std_logic;
    signal ss_dev_chg: std_logic;
    
    --  state machine
    type t_SM is (s_INIT, S_IDLE);
    signal r_stage: t_SM := s_INIT;
begin
    --  bus interface
    BUS_DEV:    entity work.dev(Behavioral)
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

    --  processes
    SAMPLER:    process(sysClk)
                begin
                    if (falling_edge(sysClk)) then
                        case (r_stage) is
                            when others =>
                                null;
                        end case;
                    end if;
                end process SAMPLER;
    
    MAIN:       process(sysClk)
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            r_stage <= s_INIT;
                        else
                            case (r_stage) is
                                when s_INIT =>
                                    --  initialization stage: we start with address 0 and see who answers it
                                    
                                    
                                
                                when others =>
                                    r_stage <= s_IDLE;
                            end case;
                        end if;
                    end if;
                end process MAIN;
    
end Behavioral;
