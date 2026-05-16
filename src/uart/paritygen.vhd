library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity paritygen is
    port (
        data: in std_logic_vector(8 downto 0);
        parity_type: in std_logic_vector(1 downto 0);   -- 0 : even, 1 : odd, 2 : mark, 3 : space
        pcheck: out std_logic
    );
end paritygen;

architecture Behavioral of paritygen is
    signal p_even: std_logic := '0';
    signal p_odd: std_logic := '0';
    
    signal pok_even: std_logic := '0';
    signal pok_odd: std_logic := '0';
    signal pok_mark: std_logic := '0';
    signal pok_space: std_logic := '0';
begin
    --  parity generators
    p_even <= (data(0) xor data(1) xor data(2) xor data(3) xor data(4) xor data(5) xor data(6) xor data(7));
    p_odd <= (data(0) xor data(1) xor data(2) xor data(3) xor data(4) xor data(5) xor data(6) xor data(7)) xor '1';
    
    --  checks
    pok_even <= '1' when (p_even=data(8)) else '0';
    pok_odd <= '1' when (p_odd=data(8)) else '0';
    pok_mark <= '1' when (data(8)='1') else '0';
    pok_space <= '1' when (data(8)='0') else '0';
    
    --  assignment
    with (parity_type) select
        pcheck <=   pok_even when "00",
                    pok_odd when "01",
                    pok_mark when "10",
                    pok_space when "11";
    
end Behavioral;
