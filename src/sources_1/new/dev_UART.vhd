library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity dev_UART is
    generic (
        --  bus topology
        bus_width: integer := 32;
        data_width: integer := 8;
        addr_width: integer := 23;
        --  device manager setup
        dev_id: integer := 1;
        dev_mem_begin: integer := 0;    --  start of memory space for the UART device
        dev_mem_end: integer := 0;      --  end of memory space for the UART device
        cpu_irq_addr_0: natural := 0;
        cpu_irq_addr_1: natural := 0
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
        bus_busy: in std_logic;
        --  interrupt lines
        irq_line_0: out std_logic;
        irq_grant_0: in std_logic;
        irq_line_1: out std_logic;
        irq_grant_1: in std_logic;
        --  hardware lines
        serial_input: in std_logic;
        serial_output: out std_logic;
        --  debug
        dbg_sdev_0: out natural;
        dbg_sdev_1: out natural;
        dbg_bridge: out natural;
        dbg_bridge_sysbusint: out natural
    );
end dev_UART;

architecture Behavioral of dev_UART is

    --  sub-bus signals
    signal sub_strobe_M: std_logic := '0';
    signal sub_strobe_S: std_logic := '0';
    signal sub_keep: std_logic := '0';
    signal sub_bus_lines: std_logic_vector(31 downto 0);
    signal sub_rq_lines: std_logic_vector(6 downto 0) := (others=>'0');
    signal sub_grant_lines: std_logic_vector(6 downto 0);
    signal sub_bus_busy: std_logic := '0';
    signal sub_bus_req_sys: std_logic_vector(6 downto 0) := (others=>'0');
    signal sub_bus_rdy_sys: std_logic_vector(6 downto 0);

    --  hardware interface
    signal hw_bus_rq_lines: std_logic_vector(7 downto 0) := (others=>'0');
    signal hw_bus_grant_lines: std_logic_vector(7 downto 0);
    signal hw_bus_busy: std_logic := '0';
    signal hw_bus_data_from: std_logic_vector(7 downto 0);
    signal hw_bus_drdy: std_logic;
    signal hw_bus_ack: std_logic := '0';
    signal hw_bus_tns: std_logic;
    signal hw_bus_data_to: std_logic_vector(7 downto 0) := (others=>'0');
    signal hw_bus_data_latch: std_logic := '0';
    signal hw_bus_data_done: std_logic := '0';
    signal hw_bus_data_in_keep: std_logic := '0';

begin

    --  bridge between system-bus and local bus
    BUS_BRIDGE: entity work.bus_bridge(Behavioral)
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
                        bus_lines => bus_lines,
                        bus_strobe_M => bus_strobe_M,
                        bus_strobe_S => bus_strobe_S,
                        bus_keep => bus_keep,
                        bus_rq => bus_rq,
                        bus_grant => bus_grant,
                        bus_busy => bus_busy,
                        --  sub-system interface
                        sub_bus_lines => sub_bus_lines,
                        sub_bus_strobe_M => sub_strobe_M,
                        sub_bus_strobe_S => sub_strobe_S,
                        sub_bus_keep => sub_keep,
                        sub_bus_rq_lines => sub_rq_lines,
                        sub_bus_grant_lines => sub_grant_lines,
                        sub_bus_busy => sub_bus_busy,
                        sub_bus_req_sys => sub_bus_req_sys,
                        sub_bus_rdy_sys => sub_bus_rdy_sys,
                        --  debug lines
                        dbg_stage => dbg_bridge,
                        dbg_stage_sysbusint => dbg_bridge_sysbusint
                    );
            
    --  shared hardware driver
    HW_DRIVER:  entity work.hwdrv_UART(Behavioral)
                    generic map (
                        data_width => data_width                        
                    ) port map (
                        sysClk => sysClk,
                        sysRstb => sysRstb,
                        --  hardware lines
                        serial_input => serial_input,
                        serial_output => serial_output,
                        --  interface
                        bus_request => hw_bus_rq_lines,
                        bus_grant => hw_bus_grant_lines,
                        bus_busy => hw_bus_busy,
                        data_out => hw_bus_data_from,
                        data_drdy => hw_bus_drdy,
                        data_ack => hw_bus_ack,
                        data_in => hw_bus_data_to,
                        data_latch => hw_bus_data_latch,
                        data_in_keep => hw_bus_data_in_keep,
                        data_done => hw_bus_data_done
                    );
        
    --  adding the sub-devices down here
    --  device 0 is a simple uart text interface
    UART_DEV0:  entity work.subdev_UART_dev0(Behavioral)
                    generic map (
                        --  bus topology
                        bus_width => bus_width,
                        data_width => data_width,
                        addr_width => addr_width,
                        --  device setup
                        dev_id => 0,
                        hw_id => 0,
                        local_mem_begin => dev_mem_begin,
                        local_mem_nvrt => 1,
                        regcfg => "generic.mem",
                        cpu_irq_addr => cpu_irq_addr_0,
                        ISR_0_pointer => 0
                    ) port map (
                        sysClk => sysClk,
                        sysRstb => sysRstb,
                        --  sub-system signals
                        bus_lines => sub_bus_lines,
                        bus_strobe_M => sub_strobe_M,
                        bus_strobe_S => sub_strobe_S,
                        bus_keep => sub_keep,
                        bus_rq => sub_rq_lines(0),
                        bus_grant => sub_grant_lines(0),
                        bus_busy => sub_bus_busy,
                        bus_req_sys => sub_bus_req_sys(0),
                        bus_rdy_sys => sub_bus_rdy_sys(0),
                        --  irq lines
                        irq_line => irq_line_0,
                        irq_grant => irq_grant_0,
                        --  hardware databus
                        hw_bus_rq => hw_bus_rq_lines(0),
                        hw_bus_grant => hw_bus_grant_lines(0),
                        hw_bus_busy => hw_bus_busy,
                        hw_data_to => hw_bus_data_to,
                        hw_keep => hw_bus_data_in_keep,
                        hw_latch => hw_bus_data_latch,
                        hw_done => hw_bus_data_done,
                        hw_data_from => hw_bus_data_from,
                        hw_drdy => hw_bus_drdy,
                        hw_ack => hw_bus_ack,
                        hw_tns => hw_bus_tns,
                        dbg => dbg_sdev_0
                    );
    
    --  device 1 is instead an ANSI terminal controller
    UART_DEV1:  entity work.subdev_UART_dev1(Behavioral)
                    generic map (
                        --  bus topology
                        bus_width => bus_width,
                        data_width => data_width,
                        addr_width => addr_width,
                        --  device setup
                        dev_id => 1,
                        hw_id => 1,
                        local_mem_begin => dev_mem_begin+65,
                        local_mem_nvrt => 65,
                        regcfg => "generic.mem",
                        cpu_irq_addr => cpu_irq_addr_1,
                        ISR_0_pointer => 0
                    ) port map (
                        sysClk => sysClk,
                        sysRstb => sysRstb,
                        --  sub-system signals
                        bus_lines => sub_bus_lines,
                        bus_strobe_M => sub_strobe_M,
                        bus_strobe_S => sub_strobe_S,
                        bus_keep => sub_keep,
                        bus_rq => sub_rq_lines(1),
                        bus_grant => sub_grant_lines(1),
                        bus_busy => sub_bus_busy,
                        bus_req_sys => sub_bus_req_sys(1),
                        bus_rdy_sys => sub_bus_rdy_sys(1),
                        --  irq lines
                        irq_line => irq_line_1,
                        irq_grant => irq_grant_1,
                        --  hardware databus
                        hw_bus_rq => hw_bus_rq_lines(1),
                        hw_bus_grant => hw_bus_grant_lines(1),
                        hw_bus_busy => hw_bus_busy,
                        hw_data_to => hw_bus_data_to,
                        hw_keep => hw_bus_data_in_keep,
                        hw_latch => hw_bus_data_latch,
                        hw_done => hw_bus_data_done,
                        hw_data_from => hw_bus_data_from,
                        hw_drdy => hw_bus_drdy,
                        hw_ack => hw_bus_ack,
                        hw_tns => hw_bus_tns,
                        --  debug
                        dbg => dbg_sdev_1
                    );
    
    --  terminations
    sub_bus_req_sys(6 downto 2) <= (others=>'0');
    sub_rq_lines(6 downto 2) <= (others=>'0');
    
    
end Behavioral;

