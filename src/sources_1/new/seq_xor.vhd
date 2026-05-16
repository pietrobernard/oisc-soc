library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity seq_xor is
    generic (
        nbits: integer := 1
    );
    port (
        vec_in: in std_logic_vector(nbits-1 downto 0);
        xor_bit: out std_logic
    );
end seq_xor;

architecture Behavioral of seq_xor is
    signal r_x: std_logic_vector(nbits downto 0) := (others=>'0');
begin

    --  generator
    g_GENERATE_FOR: for i in 1 to nbits generate
        r_x(i) <=  (r_x(i-1) xor vec_in(i-1));
    end generate g_GENERATE_FOR;

    --  output assignment
    xor_bit <= r_x(nbits);

end Behavioral;
