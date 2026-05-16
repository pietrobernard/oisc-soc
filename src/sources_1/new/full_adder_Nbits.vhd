library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity full_adder_Nbits is
    generic (
        Nbits: natural := 8
    );
    port (
        a: in std_logic_vector(Nbits-1 downto 0);
        b: in std_logic_vector(Nbits-1 downto 0);
        c_in: in std_logic;
        s: out std_logic_vector(Nbits-1 downto 0);
        c_out: out std_logic;
        ovf: out std_logic
    );
end full_adder_Nbits;

architecture Behavioral of full_adder_Nbits is
    signal carries: std_logic_vector(Nbits downto 0) := (others=>'0');
    signal sumop: std_logic_vector(Nbits-1 downto 0);
    signal ovf_0: std_logic;
    signal ovf_1: std_logic;
begin
    --  assignments
    carries(0) <= c_in;
    c_out <= carries(Nbits);
    s <= sumop;
    
    --  istantiating the Nbits 1 bit full adders
    g_GENERATE_FOR: for i in 0 to (Nbits-1) generate
        FADD_i: entity work.full_adder_1bit(Behavioral) port map (a => a(i), b => b(i), c_in => carries(i), s => sumop(i), c_out => carries(i+1));
    end generate g_GENERATE_FOR;
            
    --  overflow flag
    ovf_0 <= (a(Nbits-1) nor b(Nbits-1)) and sumop(Nbits-1);
    ovf_1 <= (a(Nbits-1) and b(Nbits-1)) and (not sumop(Nbits-1));
    ovf <= ovf_0 or ovf_1;

end Behavioral;

