library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity xor_port_nbits is
    generic (
        nbits: natural := 1
    );
    port (
        operandA: in std_logic_vector(nbits-1 downto 0);
        operandB: in std_logic_vector(nbits-1 downto 0);
        result: out std_logic_vector(nbits-1 downto 0)
    );
end xor_port_nbits;

architecture Behavioral of xor_port_nbits is

begin
    g_GENERATE_FOR: for i in 0 to nbits-1 generate
        result(i) <= operandA(i) xor operandB(i);
    end generate g_GENERATE_FOR;
end Behavioral;
