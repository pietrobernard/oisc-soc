library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity shift_unit_nbits is
    generic (
        nbits: natural := 1
    );
    port (
        operand: in std_logic_vector(nbits-1 downto 0);
        amount: in natural;
        result_L: out std_logic_vector(nbits-1 downto 0);
        result_R: out std_logic_vector(nbits-1 downto 0)
    );
end shift_unit_nbits;

architecture Behavioral of shift_unit_nbits is
    type levels is array (0 to nbits-1) of std_logic_vector(nbits-1 downto 0);
    signal result_levels_L: levels;
    signal result_levels_R: levels;
begin
    --  LEFT SHIFTING        
    result_levels_L(0)(nbits-1 downto 1) <= operand(nbits-2 downto 0);
    result_levels_L(0)(0) <= '0';
    L_GENERATE_FOR: for I in 1 to nbits-1 generate
        result_levels_L(I)(nbits-1 downto 1) <= result_levels_L(I-1)(nbits-2 downto 0);
        result_levels_L(I)(0) <= '0';
    end generate L_GENERATE_FOR;
    
    --  RIGHT SHIFTING
    result_levels_R(0)(nbits-2 downto 0) <= operand(nbits-1 downto 1);
    result_levels_R(0)(nbits-1) <= '0';
    R_GENERATE_FOR: for J in 1 to nbits-1 generate
        result_levels_R(J)(nbits-2 downto 0) <= result_levels_R(J-1)(nbits-1 downto 1);
        result_levels_R(J)(nbits-1) <= '0';
    end generate R_GENERATE_FOR;
    
    --  outputs
    result_L <= result_levels_L(amount);
    result_R <= result_levels_R(amount);
end Behavioral;
