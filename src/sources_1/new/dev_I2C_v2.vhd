library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity dev_I2C_v2 is
    generic (
        --  bus topology
        bus_width: integer := 32;
        data_width: integer := 8;
        addr_width: integer := 23;
        --  device manager setup
        dev_id: integer := 1;
        dev_mem_begin: integer := 0;    --  start of memory space for the I2C device
        dev_mem_end: integer := 0       --  end of memory space for the I2C device
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
        i2c_scl: out std_logic;
        i2c_sda: inout std_logic;
        --  debug
        dbg_stage: out natural;
        dbg_hw: out natural;
        dbg_trx: out natural;
        dbg_stage_0: out natural
    );
end dev_I2C_v2;

architecture Behavioral of dev_I2C_v2 is

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

    --  hardware interface
    signal hw_bus_rq_lines: std_logic_vector(7 downto 0) := (others=>'0');
    signal hw_bus_grant_lines: std_logic_vector(7 downto 0);
    signal hw_bus_busy: std_logic := '0';
    signal hw_bus_data_from: std_logic_vector(7 downto 0);
    signal hw_bus_drdy: std_logic;
    signal hw_bus_ack: std_logic := '0';
    signal hw_bus_data_to: std_logic_vector(7 downto 0) := (others=>'0');
    signal hw_bus_data_latch: std_logic := '0';
    signal hw_bus_data_done: std_logic := '0';
    signal hw_bus_data_in_keep: std_logic := '0';
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

    --  shared hardware driver
    HW_DRIVER:  entity work.hwdrv_I2C(Behavioral)
                    generic map (
                        data_width => data_width                        
                    ) port map (
                        sysClk => sysClk,
                        sysRstb => sysRstb,
                        --  hardware lines
                        i2c_scl => i2c_scl,
                        i2c_sda => i2c_sda,
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
                        data_done => hw_bus_data_done,
                        --  debug
                        dbg => dbg_hw,
                        dbg_trx => dbg_trx
                    );

    --  various devices here (lcd, eeprom, ecc)
    --  device 0 is the eeprom
    --  the eeprom is 32 kbytes, so I need a whole range of virtual addresses here
    --  32768 registers onto which to act
    I2C_DEV0:       entity work.subdev_I2C_dev0_v2(Behavioral)
                    generic map (
                        --  bus topology
                        bus_width => bus_width,
                        data_width => data_width,
                        addr_width => addr_width,
                        --  device setup
                        dev_id => 0,
                        local_mem_begin => dev_mem_begin,
                        local_mem_nvrt => 32769,
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
                        --  debug
                        dbg_stage => dbg_stage_0
                    );

    --  device 1 is the lcd
    --  the lcd has several registers in order to host several commands and screen manipulaton
    --  64 registers
    I2C_DEV1:       entity work.subdev_I2C_dev1_v2(Behavioral)
                    generic map (
                        --  bus topology
                        bus_width => bus_width,
                        data_width => data_width,
                        addr_width => addr_width,
                        --  device setup
                        dev_id => 1,
                        local_mem_begin => dev_mem_begin+64+32768+1,
                        local_mem_nvrt => 64,
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
                        dbg_stage => dbg_stage                                              
                    );
                    
    --  terminations
    sub_bus_req_sys(6 downto 2) <= (others=>'0');
    sub_rq_lines(6 downto 2) <= (others=>'0');
end Behavioral;
