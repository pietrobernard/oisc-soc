library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity multiplexer_Nbits is
    generic (
        nbits: natural := 1
    );
    port (
        chA: in std_logic_vector(nbits-1 downto 0);
        chB: in std_logic_vector(nbits-1 downto 0);
        chO: out std_logic_vector(nbits-1 downto 0);
        sel: in std_logic
    );
end multiplexer_Nbits;

architecture Behavioral of multiplexer_Nbits is

begin
    with (sel) select
        chO <= chA when '0', chB when others;

end Behavioral;
