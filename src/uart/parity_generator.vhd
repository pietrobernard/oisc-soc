library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity parity_generator is
    port (
        data_input: in std_logic_vector(7 downto 0);
        parity_bits: out std_logic_vector(3 downto 0)
    );
end parity_generator;

architecture Behavioral of parity_generator is
    signal parities: std_logic_vector(3 downto 0) := (others=>'0');
begin
    --  generates the appropriate parity bit
    --  for instance if we have 01011 with even parity
    --  it outputs 1
    parities(0) <= (data_input(0) xor data_input(1) xor data_input(2) xor data_input(3) xor data_input(4) xor data_input(5) xor data_input(6) xor data_input(7));
    parities(1) <= (data_input(0) xor data_input(1) xor data_input(2) xor data_input(3) xor data_input(4) xor data_input(5) xor data_input(6) xor data_input(7) xor '1');
    parities(2) <= '1';
    parities(3) <= '0';
    
    --  output
    parity_bits <= parities;
    
end Behavioral;
