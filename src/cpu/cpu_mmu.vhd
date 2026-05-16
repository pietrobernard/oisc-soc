library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_mmu is
    generic (
        --  bus topology
        bus_width: integer := 32;
        data_width: integer := 8;
        addr_width: integer := 23
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  bus lines and logic
        bus_lines: inout std_logic_vector(bus_width-1 downto 0);
        bus_strobe_M: inout std_logic;
        bus_strobe_S: inout std_logic;
        bus_keep: inout std_logic
    );
end cpu_mmu;

architecture Behavioral of cpu_mmu is

begin


end Behavioral;
--  la mmu gestisce l'accesso alla memoria. per come sto adesso quindi e' possibile sia l'accesso diretto periferica-periferica e cpu-periferica, sia anche
--  l'accesso alla memoria centrale dove le periferiche possono a loro volta avere il loro spazio riservato (memoria fisica quindi non residente su fpga)
--  