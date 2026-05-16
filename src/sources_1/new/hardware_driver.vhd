library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

--  the hardware driver uses another kind of bus
--  this driver must be wrapped with the full driver of the specific
--  piece of hardware.
entity hardware_driver is
    generic (
        --  bus topology
        data_width: integer := 8;
        ndevs: natural := 8
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  INTERFACE WITH HARDWARE BUS
        --  system bus interface signals
        bus_request: in std_logic_vector(ndevs-1 downto 0);
        bus_grant: out std_logic_vector(ndevs-1 downto 0);
        bus_busy: out std_logic;
        --  output databus lanes
        data_out: out std_logic_vector(data_width-1 downto 0);
        data_drdy: out std_logic;
        data_ack: in std_logic;
        --  input databus lanes
        data_in: in std_logic_vector(data_width-1 downto 0);
        data_latch: in std_logic;
        data_done: out std_logic
        --  wrapper signals
        
    );
end hardware_driver;

architecture Behavioral of hardware_driver is

begin
    --  hardware access arbiter
    HWARB:  entity work.bus_arb(Behavioral)
                generic map (
                    n_rq_lines => ndevs
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  request lines
                    rq_lines => bus_request,
                    grant_lines => bus_grant,
                    busy => bus_busy
                );

    --  so, when one of the subdevs wants to access this hardware,
    --  it must gain control of the bus and drive the input data lanes
    --  and read the output lanes.
    

end Behavioral;
