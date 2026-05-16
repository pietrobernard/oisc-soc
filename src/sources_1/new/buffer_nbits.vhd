library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity buffer_nbits is
    generic (
        w: natural := 8
    );
    port (
        d: in std_logic_vector(w-1 downto 0);
        q: out std_logic_vector(w-1 downto 0);
        oe: in std_logic
    );
end buffer_nbits;

architecture Behavioral of buffer_nbits is

begin

    with oe select
        q <= d when '1',
            (others=>'Z') when others;

end Behavioral;
