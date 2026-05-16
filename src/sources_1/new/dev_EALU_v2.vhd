library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

--  EALU is an Extended ALU that provides the cpu core
--  with some support operations that can be accessed by reading and writing
--  to appropriate registers in the usual manner.
--  specifically, the EALU includes ways to do bit manipulation and logical operations
entity dev_EALU_v2 is
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
        bus_busy: in std_logic
    );
end dev_EALU_v2;

architecture Behavioral of dev_EALU_v2 is
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

begin
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
    
end Behavioral;

