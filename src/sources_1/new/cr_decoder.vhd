library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cr_decoder is
    port (
        encoded_in: in std_logic_vector(6 downto 0);
        first_digit: out std_logic_vector(3 downto 0);
        secon_digit: out std_logic_vector(3 downto 0)
    );
end cr_decoder;

architecture Behavioral of cr_decoder is
    signal wf1: std_logic_vector(4 downto 0);
    signal wf0: std_logic_vector(9 downto 0);
    
    signal ws0: std_logic_vector(7 downto 0);
    signal ws1: std_logic_vector(10 downto 0);
    signal ws2: std_logic_vector(10 downto 0);
begin
    --  first digit: f6,f7,f8,f9
    first_digit(3) <= '0';
    first_digit(2) <= encoded_in(6) or (encoded_in(5) and encoded_in(4)) or (encoded_in(5) and encoded_in(3));
        
    wf1(0) <= encoded_in(5) and (not encoded_in(4)) and (not encoded_in(3));
    wf1(1) <= encoded_in(4) and encoded_in(3) and encoded_in(2);
    wf1(2) <= encoded_in(6);
    wf1(3) <= (not encoded_in(5)) and (encoded_in(4)) and (encoded_in(3));
    wf1(4) <= (not encoded_in(5)) and (encoded_in(4)) and (encoded_in(2));
    first_digit(1) <= wf1(0) or wf1(1) or wf1(2) or wf1(3) or wf1(4);
    
    wf0(0) <= encoded_in(5) and (not encoded_in(3)) and encoded_in(1);
    wf0(1) <= encoded_in(6) and encoded_in(3);
    wf0(2) <= encoded_in(5) and encoded_in(4) and encoded_in(3) and (not encoded_in(2));
    wf0(3) <= encoded_in(5) and (not encoded_in(3)) and encoded_in(2);
    wf0(4) <= encoded_in(6) and encoded_in(2) and encoded_in(1);
    wf0(5) <= (not encoded_in(5)) and encoded_in(4) and (not encoded_in(3)) and (not encoded_in(2));
    wf0(6) <= encoded_in(5) and (not encoded_in(4)) and (not encoded_in(3));
    wf0(7) <= (not encoded_in(5)) and (not encoded_in(4)) and (encoded_in(3)) and (encoded_in(2));
    wf0(8) <= (not encoded_in(5)) and encoded_in(3) and encoded_in(2) and encoded_in(1);
    wf0(9) <= (not encoded_in(5)) and (not encoded_in(4)) and encoded_in(3) and encoded_in(1);
    first_digit(0) <= wf0(0) or wf0(1) or wf0(2) or wf0(3) or wf0(4) or wf0(5) or wf0(6) or wf0(7) or wf0(8) or wf0(9);
    
    
    --  second digit: f10, f11, f12, f13
    ws0(0) <= encoded_in(6) and (not encoded_in(3)) and encoded_in(2) and (not encoded_in(1));
    ws0(1) <= encoded_in(6) and encoded_in(3) and encoded_in(2) and encoded_in(1);
    ws0(2) <= encoded_in(5) and encoded_in(4) and (not encoded_in(3)) and (not encoded_in(2)) and (not encoded_in(1));    
    ws0(3) <= encoded_in(5) and encoded_in(4) and encoded_in(3) and (not encoded_in(2)) and encoded_in(1);
    ws0(4) <= encoded_in(5) and (not encoded_in(4)) and (not encoded_in(3)) and encoded_in(2) and encoded_in(1);
    ws0(5) <= (not encoded_in(6)) and (not encoded_in(5)) and (not encoded_in(4)) and encoded_in(3) and (not encoded_in(2)) and (not encoded_in(1));
    ws0(6) <= (not encoded_in(5)) and encoded_in(4) and encoded_in(3) and encoded_in(2) and (not encoded_in(1));
    ws0(7) <= (not encoded_in(5)) and encoded_in(4) and (not encoded_in(3)) and (not encoded_in(2)) and encoded_in(1);
    secon_digit(3) <= ws0(0) or ws0(1) or ws0(2) or ws0(3) or ws0(4) or ws0(5) or ws0(6) or ws0(7);
    
    ws1(0) <= encoded_in(5) and (not encoded_in(4)) and encoded_in(2) and (not encoded_in(1));
    ws1(1) <= (not encoded_in(6)) and (not encoded_in(4)) and encoded_in(3) and encoded_in(2) and encoded_in(1);
    ws1(2) <= (not encoded_in(6)) and (not encoded_in(5)) and (not encoded_in(4)) and (not encoded_in(3)) and encoded_in(2);
    ws1(3) <= encoded_in(4) and encoded_in(3) and (not encoded_in(2)) and (not encoded_in(1));
    ws1(4) <= encoded_in(5) and encoded_in(4) and (not encoded_in(3)) and encoded_in(2) and encoded_in(1);
    ws1(5) <= encoded_in(6) and (not encoded_in(3)) and (not encoded_in(2));
    ws1(6) <= encoded_in(6) and encoded_in(3) and encoded_in(2) and (not encoded_in(1));
    ws1(7) <= encoded_in(6) and (not encoded_in(2)) and encoded_in(1);
    ws1(8) <= (not encoded_in(5)) and encoded_in(4) and (not encoded_in(2)) and (not encoded_in(1));
    ws1(9) <= (not encoded_in(5)) and encoded_in(4) and encoded_in(3) and (not encoded_in(2));
    ws1(10)<= encoded_in(5) and (not encoded_in(4)) and (not encoded_in(3)) and (not encoded_in(2)) and encoded_in(1);
    secon_digit(2) <= ws1(0) or ws1(1) or ws1(2) or ws1(3) or ws1(4) or ws1(5) or ws1(6) or ws1(7) or ws1(8) or ws1(9) or ws1(10);
    
    ws2(0) <= (not encoded_in(5)) and (not encoded_in(4)) and (not encoded_in(3)) and (not encoded_in(2)) and encoded_in(1);
    ws2(1) <= (not encoded_in(6)) and (not encoded_in(5)) and (not encoded_in(3)) and encoded_in(2) and encoded_in(1);
    ws2(2) <= encoded_in(6) and encoded_in(3) and (not encoded_in(1));
    ws2(3) <= encoded_in(5) and encoded_in(4) and encoded_in(3) and (not encoded_in(2)) and (not encoded_in(1));
    ws2(4) <= encoded_in(5) and (not encoded_in(3)) and encoded_in(2) and (not encoded_in(1));
    ws2(5) <= encoded_in(5) and encoded_in(3) and encoded_in(2) and encoded_in(1);
    ws2(6) <= (not encoded_in(5)) and encoded_in(4) and (not encoded_in(3)) and (not encoded_in(2)) and (not encoded_in(1));
    ws2(7) <= (not encoded_in(5)) and encoded_in(4) and encoded_in(3) and (not encoded_in(2)) and encoded_in(1);
    ws2(8) <= encoded_in(5) and (not encoded_in(4)) and (not encoded_in(3)) and (not encoded_in(1));
    ws2(9) <= encoded_in(5) and (not encoded_in(4)) and encoded_in(3) and encoded_in(1);
    ws2(10)<= (not encoded_in(5)) and (not encoded_in(4)) and encoded_in(3) and encoded_in(2) and (not encoded_in(1));
    secon_digit(1) <= ws2(0) or ws2(1) or ws2(2) or ws2(3) or ws2(4) or ws2(5) or ws2(6) or ws2(7) or ws2(8) or ws2(9) or ws2(10);
    
    secon_digit(0) <= encoded_in(0);
end Behavioral;
