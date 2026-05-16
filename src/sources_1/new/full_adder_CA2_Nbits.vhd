library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity full_adder_CA2_Nbits is
    generic (
        Nbits: natural := 8
    );
    port (
        a: in std_logic_vector(Nbits-1 downto 0);
        b: in std_logic_vector(Nbits-1 downto 0);
        ds: in natural;                                 --  data size of the output: 8, 16 or 32 bits
        s: out std_logic_vector(Nbits-1 downto 0);
        ovf: out std_logic; --  overflow flag
        zf: out std_logic;  --  zero flag
        pf: out std_logic;  --  parity flag (even)
        sf: out std_logic   --  sign flag
    );
end full_adder_CA2_Nbits;

architecture Behavioral of full_adder_CA2_Nbits is
    signal inv_a: std_logic_vector(Nbits-1 downto 0);
    signal a_in: std_logic_vector(Nbits-1 downto 0);
    signal s_out: std_logic_vector(Nbits-1 downto 0);
    signal r_zf: std_logic_vector(Nbits-1 downto 0);
    signal r_pf: std_logic_vector(Nbits-1 downto 0);
begin
    --  first step is to invert A and sum 1, so:
    g_INV_FOR: for j in 0 to (Nbits-1) generate
        inv_a(j) <= (a(j) xor '1');
    end generate g_INV_FOR;
    
    --  adding 1 to the inverted A
    CA2_ADDER:  entity work.full_adder_Nbits(Behavioral)
                generic map (Nbits => Nbits) port map (
                    a => (others=>'0'), --  0
                    b => inv_a,         --  preceding sum
                    c_in => '1',        --  adding 1
                    s => a_in           --  inv(A) + 1 output
                );
    --  this adder performs the b + (-a) addition
    BASE_ADDER: entity work.full_adder_Nbits(Behavioral)
                generic map (Nbits => Nbits) port map (
                    a => a_in,          --  a operand
                    b => b,             --  b operand
                    c_in => '0',        --  input carry
                    s => s_out,         --  output sum
                    ovf => ovf          --  overflow flag
                );
    --  assignment
    s <= s_out;
        
    --  zero flag generator
    r_zf(0) <= s_out(0);
    g_ZF_FOR: for i in 1 to (Nbits-1) generate
        r_zf(i) <= (r_zf(i-1) or s_out(i));
    end generate g_ZF_FOR;
    zf <= not r_zf(ds-1);
    
    --  parity flag
    r_pf(0) <= s_out(0);
    g_PF_FOR: for k in 1 to (Nbits-1) generate
        r_pf(k) <= (r_pf(k-1) xor s_out(k));
    end generate g_PF_FOR;
    pf <= r_pf(ds-1);
    
    --  sign flag
    sf <= s_out(ds-1);
    
end Behavioral;
