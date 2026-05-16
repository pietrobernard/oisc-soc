library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity inout_port is
    generic (
        nbits:  integer := 1
    );
    port(
        io:         inout   std_logic_vector(nbits-1 downto 0);
        data_to:    in  std_logic_vector(nbits-1 downto 0);
        data_from:  out std_logic_vector(nbits-1 downto 0);
        dir:        in  std_logic
    );
end inout_port;

architecture Behavioral of inout_port is
    signal r_data_to:   std_logic_vector(nbits-1 downto 0) := (others=>'0');
    signal r_data_from: std_logic_vector(nbits-1 downto 0) := (others=>'0');
begin
    --  assignments
    r_data_to <= data_to;
    data_from <= r_data_from;

    with (dir) select
        io <=   r_data_to when '1',
                (others=>'Z') when others;
    
    with (dir) select
        r_data_from <= (io) when '0',
                        (others=>'Z') when others;

    

    --with (dir) select
    --    io <= (others=>'Z') when '0',
    --          r_data_to     when '1',
    --          (others=>'Z') when others;
    
    --with (dir) select
    --    r_data_from <= (io) when '0',
    --                   (others=>'Z') when '1',
    --                   (others=>'Z') when others;

end Behavioral;
