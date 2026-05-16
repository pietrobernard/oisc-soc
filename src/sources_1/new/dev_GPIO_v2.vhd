library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity dev_GPIO_v2 is
    generic (
        --  bus topology
        bus_width: integer := 32;
        data_width: integer := 8;
        addr_width: integer := 23;
        --  device manager setup
        dev_id: integer := 3;
        dev_mem_begin: integer := 0;    --  start of memory space for the UART device
        dev_mem_end: integer := 0       --  end of memory space for the UART device
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
        portA: inout std_logic_vector(data_width-1 downto 0);
        drdyA: in std_logic;
        dackA: out std_logic;
        portB: inout std_logic_vector(data_width-1 downto 0);
        drdyB: in std_logic;
        dackB: out std_logic--;
        --  debug
        --dbg_0: out std_logic_vector(7 downto 0);
        --dbg_1: out std_logic_vector(7 downto 0);
        --dbg_S: out std_logic;
        --dbg_M: out std_logic
    );
end dev_GPIO_v2;

architecture Behavioral of dev_GPIO_v2 is

    --  sub-bus signals
    signal sub_strobe_M: std_logic := '0';
    signal sub_strobe_S: std_logic := '0';
    signal sub_keep: std_logic := '0';
    signal sub_done_S: std_logic := '0';
    signal sub_bus_lines: std_logic_vector(31 downto 0);
    signal sub_rq_lines: std_logic_vector(6 downto 0) := (others=>'0');
    signal sub_grant_lines: std_logic_vector(6 downto 0);
    signal sub_bus_busy: std_logic := '0';
    signal sub_bus_req_sys: std_logic_vector(6 downto 0) := (others=>'0');
    signal sub_bus_rdy_sys: std_logic_vector(6 downto 0);
    signal sub_bus_err_sys: std_logic_vector(6 downto 0);
    
begin

    --  bridge between system-bus and local bus
    BUS_BRIDGE: entity work.bus_bridge_v2(Behavioral)
                    generic map (
                        --  system bus topology
                        bus_width => bus_width,
                        data_width => data_width,
                        addr_width => addr_width,
                        --  memory specifications
                        dev_id => dev_id,
                        dev_mem_begin => dev_mem_begin,
                        dev_mem_end => dev_mem_end
                    ) port map (
                        sysClk => sysClk,
                        sysRstb => sysRstb,
                        --  system bus interface signals
                        ext_bus_lines => bus_lines,
                        ext_bus_strobe_M => bus_strobe_M,
                        ext_bus_strobe_S => bus_strobe_S,
                        ext_bus_keep => bus_keep,
                        ext_bus_done_S => bus_done_S,
                        ext_bus_rq => bus_rq,
                        ext_bus_grant => bus_grant,
                        ext_bus_busy => bus_busy,
                        --  sub-system interface
                        int_bus_lines => sub_bus_lines,
                        int_bus_strobe_M => sub_strobe_M,
                        int_bus_strobe_S => sub_strobe_S,
                        int_bus_keep => sub_keep,
                        int_bus_done_S => sub_done_S,
                        int_bus_rq_lines => sub_rq_lines,
                        int_bus_grant_lines => sub_grant_lines,
                        int_bus_busy => sub_bus_busy,
                        --  booking system
                        int2ext_req => sub_bus_req_sys,
                        int2ext_rdy => sub_bus_rdy_sys,
                        int2ext_err => sub_bus_err_sys
                    );
        
    --  adding the sub-devices down here
    --  device 0 is a simple keyboard controller
    GPIO_PORTA: entity work.subdev_GPIO_kbd_v2(Behavioral)
                    generic map (
                        --  bus topology
                        bus_width => bus_width,
                        data_width => data_width,
                        addr_width => addr_width,
                        --  device setup
                        dev_id => 0,
                        local_mem_begin => dev_mem_begin,
                        local_mem_nvrt => 4,
                        regcfg => "generic.mem"
                    ) port map (
                        sysClk => sysClk,
                        sysRstb => sysRstb,
                        --  sub-system signals
                        bus_lines => sub_bus_lines,
                        bus_strobe_M => sub_strobe_M,
                        bus_strobe_S => sub_strobe_S,
                        bus_keep => sub_keep,
                        bus_done_S => sub_done_S,
                        bus_rq => sub_rq_lines(0),
                        bus_grant => sub_grant_lines(0),
                        bus_busy => sub_bus_busy,
                        --  booking system
                        bus_req_sys => sub_bus_req_sys(0),
                        bus_rdy_sys => sub_bus_rdy_sys(0),
                        bus_err_sys => sub_bus_err_sys(0),
                        --  hardware lines
                        extport => portA,
                        strobe_S => drdyA,
                        strobe_M => dackA--,
                        --  debug
                        --dbg_0 => dbg_0,
                        --dbg_1 => dbg_1,
                        --dbg_signal_strobe_S => dbg_S,
                        --dbg_signal_strobe_M => dbg_M
                    );
    
    --  device 1 is a general purpose i/o pin header
    GPIO_PORTB: entity work.subdev_GPIO_v2(Behavioral)
                generic map (
                    --  bus topology
                    bus_width => bus_width,
                    data_width => data_width,
                    addr_width => addr_width,
                    --  device setup
                    dev_id => 1,
                    local_mem_begin => dev_mem_begin,
                    local_mem_nvrt => 4,
                    regcfg => "generic.mem"
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  sub-system signals
                    bus_lines => sub_bus_lines,
                    bus_strobe_M => sub_strobe_M,
                    bus_strobe_S => sub_strobe_S,
                    bus_keep => sub_keep,
                    bus_done_S => sub_done_S,
                    bus_rq => sub_rq_lines(1),
                    bus_grant => sub_grant_lines(1),
                    bus_busy => sub_bus_busy,
                    --  booking system
                    bus_req_sys => sub_bus_req_sys(1),
                    bus_rdy_sys => sub_bus_rdy_sys(1),
                    bus_err_sys => sub_bus_err_sys(1),
                    --  hardware links with the portB controller
                    extport => portB,
                    strobe_S => drdyB,
                    strobe_M => dackB
                );
    
    --  terminations
    sub_bus_req_sys(6 downto 2) <= (others=>'0');
    sub_rq_lines(6 downto 2) <= (others=>'0');
    
    
end Behavioral;

