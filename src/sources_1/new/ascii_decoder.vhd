library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ascii_decoder is
    port (
        encoded: in std_logic_vector(12 downto 0);
        --ascii_code: out std_logic_vector(7 downto 0);
        fore_color: out std_logic_vector(2 downto 0);
        back_color: out std_logic_vector(2 downto 0)
    );
end ascii_decoder;

architecture Behavioral of ascii_decoder is
    signal back_color_w2: std_logic_vector(5 downto 0);
    signal back_color_w1: std_logic_vector(5 downto 0);
    signal back_color_w0: std_logic_vector(5 downto 0);
    
    signal fore_color_w2: std_logic_vector(5 downto 0);
    signal fore_color_w1: std_logic_vector(5 downto 0);
    signal fore_color_w0: std_logic_vector(5 downto 0);
    
    --signal ascii_code_w6: std_logic_vector(4 downto 0);
    --signal ascii_code_w5: std_logic_vector(4 downto 0);
    --signal ascii_code_w4: std_logic_vector(4 downto 0);
    --signal ascii_code_w3: std_logic_vector(4 downto 0);
    --signal ascii_code_w2: std_logic_vector(4 downto 0);
    --signal ascii_code_w1: std_logic_vector(4 downto 0);
    --signal ascii_code_w0: std_logic_vector(4 downto 0);    
begin
    --  background color generator
    back_color_w2(0) <= ((not encoded(11)) and (not encoded(6)) and (encoded(2)));
    back_color_w2(1) <= ((not encoded(11)) and (not encoded(7)) and (encoded(2)));
    back_color_w2(2) <= ((not encoded(11)) and (not encoded(8)) and (encoded(2)));
    back_color_w2(3) <= ((not encoded(11)) and (not encoded(9)) and (encoded(2)));
    back_color_w2(4) <= ((not encoded(11)) and (not encoded(10)) and (encoded(2)));
    back_color_w2(5) <= ((not encoded(12)) and encoded(2));
    back_color(2) <= back_color_w2(0) or back_color_w2(1) or back_color_w2(2) or back_color_w2(3) or back_color_w2(4) or back_color_w2(5);
    
    back_color_w1(0) <= ((not encoded(11)) and (not encoded(6)) and (encoded(1)));
    back_color_w1(1) <= ((not encoded(11)) and (not encoded(7)) and (encoded(1)));
    back_color_w1(2) <= ((not encoded(11)) and (not encoded(8)) and (encoded(1)));
    back_color_w1(3) <= ((not encoded(11)) and (not encoded(9)) and (encoded(1)));
    back_color_w1(4) <= ((not encoded(11)) and (not encoded(10)) and (encoded(1)));
    back_color_w1(5) <= ((not encoded(12)) and encoded(1));
    back_color(1) <= back_color_w1(0) or back_color_w1(1) or back_color_w1(2) or back_color_w1(3) or back_color_w1(4) or back_color_w1(5);
    
    back_color_w0(0) <= ((not encoded(11)) and (not encoded(6)) and (encoded(0)));
    back_color_w0(1) <= ((not encoded(11)) and (not encoded(7)) and (encoded(0)));
    back_color_w0(2) <= ((not encoded(11)) and (not encoded(8)) and (encoded(0)));
    back_color_w0(3) <= ((not encoded(11)) and (not encoded(9)) and (encoded(0)));
    back_color_w0(4) <= ((not encoded(11)) and (not encoded(10)) and (encoded(0)));
    back_color_w0(5) <= ((not encoded(12)) and encoded(0));
    back_color(0) <= back_color_w0(0) or back_color_w0(1) or back_color_w0(2) or back_color_w0(3) or back_color_w0(4) or back_color_w0(5);
        
    --  foreground color generator
    fore_color_w2(0) <= ((not encoded(11)) and (not encoded(6)) and (encoded(5)));
    fore_color_w2(1) <= ((not encoded(11)) and (not encoded(7)) and (encoded(5)));
    fore_color_w2(2) <= ((not encoded(11)) and (not encoded(8)) and (encoded(5)));
    fore_color_w2(3) <= ((not encoded(11)) and (not encoded(9)) and (encoded(5)));
    fore_color_w2(4) <= ((not encoded(11)) and (not encoded(10)) and (encoded(5)));
    fore_color_w2(5) <= ((not encoded(12)) and encoded(5));
    fore_color(2) <= fore_color_w2(0) or fore_color_w2(1) or fore_color_w2(2) or fore_color_w2(3) or fore_color_w2(4) or fore_color_w2(5);
    
    fore_color_w1(0) <= ((not encoded(11)) and (not encoded(6)) and (encoded(4)));
    fore_color_w1(1) <= ((not encoded(11)) and (not encoded(7)) and (encoded(4)));
    fore_color_w1(2) <= ((not encoded(11)) and (not encoded(8)) and (encoded(4)));
    fore_color_w1(3) <= ((not encoded(11)) and (not encoded(9)) and (encoded(4)));
    fore_color_w1(4) <= ((not encoded(11)) and (not encoded(10)) and (encoded(4)));
    fore_color_w1(5) <= ((not encoded(12)) and encoded(4));
    fore_color(1) <= fore_color_w1(0) or fore_color_w1(1) or fore_color_w1(2) or fore_color_w1(3) or fore_color_w1(4) or fore_color_w1(5);
    
    fore_color_w0(0) <= ((not encoded(11)) and (not encoded(6)) and (encoded(3)));
    fore_color_w0(1) <= ((not encoded(11)) and (not encoded(7)) and (encoded(3)));
    fore_color_w0(2) <= ((not encoded(11)) and (not encoded(8)) and (encoded(3)));
    fore_color_w0(3) <= ((not encoded(11)) and (not encoded(9)) and (encoded(3)));
    fore_color_w0(4) <= ((not encoded(11)) and (not encoded(10)) and (encoded(3)));
    fore_color_w0(5) <= ((not encoded(12)) and encoded(3));
    fore_color(0) <= fore_color_w0(0) or fore_color_w0(1) or fore_color_w0(2) or fore_color_w0(3) or fore_color_w0(4) or fore_color_w0(5);
            
    --  ascii code generator
    --ascii_code_w6(0) <= (encoded(12) and (not encoded(11)) and (not encoded(6)));
    --ascii_code_w6(1) <= (encoded(12) and (not encoded(11)) and (not encoded(7)));
    --ascii_code_w6(2) <= (encoded(12) and (not encoded(11)) and (not encoded(8)));
    --ascii_code_w6(3) <= (encoded(12) and (not encoded(11)) and (not encoded(9)));
    --ascii_code_w6(4) <= (encoded(12) and (not encoded(11)) and (not encoded(10)));
    --ascii_code(6) <= ascii_code_w6(0) or ascii_code_w6(1) or ascii_code_w6(2) or ascii_code_w6(3) or ascii_code_w6(4);  
    
    --ascii_code(5) <= (not encoded(12)) and (encoded(11));
    
    --ascii_code_w4(0) <= ((not encoded(11)) and (encoded(10)) and (not encoded(6)));
    --ascii_code_w4(1) <= ((not encoded(11)) and (encoded(10)) and (not encoded(7)));
    --ascii_code_w4(2) <= ((not encoded(11)) and (encoded(10)) and (not encoded(8)));
    --ascii_code_w4(3) <= ((not encoded(11)) and (encoded(10)) and (not encoded(9)));
    --ascii_code_w4(4) <= (not encoded(12)) and (encoded(10));
    --ascii_code(4) <= ascii_code_w4(0) or ascii_code_w4(1) or ascii_code_w4(2) or ascii_code_w4(3) or ascii_code_w4(4);
    
    --ascii_code_w3(0) <= ((not encoded(11)) and (encoded(9)) and (not encoded(6)));
    --ascii_code_w3(1) <= ((not encoded(11)) and (encoded(9)) and (not encoded(7)));
    --ascii_code_w3(2) <= ((not encoded(11)) and (encoded(9)) and (not encoded(8)));
    --ascii_code_w3(3) <= ((not encoded(11)) and (not encoded(10)) and (encoded(9)));
    --ascii_code_w3(4) <= (not encoded(12)) and (encoded(9));
    --ascii_code(3) <= ascii_code_w3(0) or ascii_code_w3(1) or ascii_code_w3(2) or ascii_code_w3(3) or ascii_code_w3(4);
    
    --ascii_code_w2(0) <= ((not encoded(11)) and (encoded(8)) and (not encoded(6)));
    --ascii_code_w2(1) <= ((not encoded(11)) and (encoded(8)) and (not encoded(7)));
    --ascii_code_w2(2) <= ((not encoded(11)) and (not encoded(9)) and (encoded(8)));
    --ascii_code_w2(3) <= ((not encoded(11)) and (not encoded(10)) and (encoded(8)));
    --ascii_code_w2(4) <= (not encoded(12)) and (encoded(8));
    --ascii_code(2) <= ascii_code_w2(0) or ascii_code_w2(1) or ascii_code_w2(2) or ascii_code_w2(3) or ascii_code_w2(4);
    
    --ascii_code_w1(0) <= ((not encoded(11)) and (encoded(7)) and (not encoded(6)));
    --ascii_code_w1(1) <= ((not encoded(11)) and (not encoded(8)) and (encoded(7)));
    --ascii_code_w1(2) <= ((not encoded(11)) and (not encoded(9)) and (encoded(7)));
    --ascii_code_w1(3) <= ((not encoded(11)) and (not encoded(10)) and (encoded(7)));
    --ascii_code_w1(4) <= (not encoded(12)) and (encoded(7));
    --ascii_code(1) <= ascii_code_w1(0) or ascii_code_w1(1) or ascii_code_w1(2) or ascii_code_w1(3) or ascii_code_w1(4);
    
    --ascii_code_w0(0) <= ((not encoded(11)) and (not encoded(7)) and (encoded(6)));
    --ascii_code_w0(1) <= ((not encoded(11)) and (not encoded(8)) and (encoded(6)));
    --ascii_code_w0(2) <= ((not encoded(11)) and (not encoded(9)) and (encoded(6)));
    --ascii_code_w0(3) <= ((not encoded(11)) and (not encoded(10)) and (encoded(6)));
    --ascii_code_w0(4) <= (not encoded(12)) and (encoded(6));
    --ascii_code(0) <= ascii_code_w0(0) or ascii_code_w0(1) or ascii_code_w0(2) or ascii_code_w0(3) or ascii_code_w0(4);
    

end Behavioral;
