library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity const_types is
end const_types;

architecture Behavioral of const_types is
begin
end Behavioral;

package const_types is
    --  bus interface types
    type t_SM is (s_INIT, s_IDLE, s_SLAVE_0, s_SLAVE_1, s_SLAVE_2, s_SLAVE_3, s_SLAVE_4, s_SLAVE_5, s_SLAVE_6,
                    s_MASTER_0, s_MASTER_1, s_MASTER_2, s_MASTER_3, s_MASTER_4, s_MASTER_5, s_MASTER_6, s_MASTER_7, s_MASTER_8, s_MASTER_9);
end package const_types;

package body const_types is
end package body const_types;