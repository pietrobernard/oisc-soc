library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity bus_arb is
    generic (
        n_rq_lines: integer := 8
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  request lines
        rq_lines: in std_logic_vector(n_rq_lines-1 downto 0);
        grant_lines: out std_logic_vector(n_rq_lines-1 downto 0);
        busy: out std_logic
    );
end bus_arb;

architecture Behavioral of bus_arb is
    signal r_busy: std_logic := '0';
    signal r_grant_lines: std_logic_vector(n_rq_lines-1 downto 0) := (others=>'0');
    type t_SM is (s_INIT, s_IDLE, s_SCAN_0, s_HOLD_0, s_HOLD_1);
    signal r_stage: t_SM := s_INIT;
    
    --  backup register
    signal r_rq_lines: std_logic_vector(n_rq_lines-1 downto 0) := (others=>'0');
    signal r_bak_lines: std_logic_vector(n_rq_lines-1 downto 0) := (others=>'0');
    signal r_or: std_logic := '0';
    constant r_zeros: std_logic_vector(n_rq_lines-1 downto 0) := (others=>'0');
begin
    --  xorrer
    ORRER:      entity work.seq_or(Behavioral)
                    generic map (nbits => n_rq_lines)
                    port map (
                        vec_in => r_bak_lines,
                        or_bit => r_or
                    );

    --  sampler
    SAMPLER:    process(sysClk)
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            --  reset
                            r_rq_lines <= (others=>'0');
                        else
                            --  go
                            case (r_stage) is
                                when s_IDLE =>
                                    --  waiting for something to occurr on the bus
                                    r_rq_lines <= rq_lines;
                                
                                when s_HOLD_0 =>
                                    r_rq_lines <= rq_lines;
                                
                                when others =>
                                    r_rq_lines <= r_rq_lines;
                            
                            end case;
                        end if;
                    end if;
                end process SAMPLER;
    
    --  main
    MAIN:       process(sysClk)
                    variable lIdx: natural := 0;
                    variable pcount: natural := 0;  --  this was added to solve the bug that in case a device books the bus but then retreats it before it is serviced, that the arbiter could get caught in an infinite loop
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                        
                        else
                            case (r_stage) is
                                when s_INIT =>
                                    r_stage <= s_IDLE;
                                
                                when s_IDLE =>
                                    --  waiting for something to occurr on the bus
                                    lIdx := 0;
                                    pcount := 0;
                                    r_bak_lines <= r_rq_lines;
                                    if (r_rq_lines=r_zeros) then
                                        --  no request issued
                                        r_stage <= s_IDLE;
                                    else
                                        --  one or more requests have been issued
                                        r_stage <= s_SCAN_0;
                                    end if;
                            
                                when s_SCAN_0 =>
                                    if (r_rq_lines(lIdx)='1') then
                                        --  bus request on line 'lIdx'
                                        r_grant_lines(lIdx) <= '1';
                                        r_busy <= '1';
                                        r_stage <= s_HOLD_0;
                                    else
                                        --  going to next line
                                        if (lIdx=7) then
                                            lIdx := 0;
                                        else
                                            lIdx := lIdx + 1;
                                        end if;
                                        --  checking pcount
                                        if (pcount=8) then
                                            --  we've checked em all, there is nothing, so
                                            r_stage <= s_IDLE;
                                        else
                                            pcount := pcount + 1;
                                            r_stage <= s_SCAN_0;
                                        end if;
                                    end if;
                            
                                when s_HOLD_0 =>
                                    if (r_rq_lines(lIdx)='0') then
                                        --  bus release on line 'lIdx'
                                        r_grant_lines(lIdx) <= '0';
                                        r_bak_lines(lIdx) <= '0';
                                        r_busy <= '0';
                                        r_stage <= s_HOLD_1;
                                    else
                                        --  bus is being used but I must also detect eventual 'zombie' states
                                        --  a zombie state could appear when a device books a bus or intends to use it
                                        --  but then for some other issue it fails to actually use it.
                                        --  when this happens the bus must be freed. How to detect this? one idea could be
                                        --  to look for strobe_M : if no strobe M occurrs within a certain amount of clock cycles
                                        --  then the bus must be released since a zombie condition occurred.
                                        r_stage <= s_HOLD_0;
                                    end if;
                            
                                when s_HOLD_1 =>
                                    --  now we must see if there's other requests on the snapshot
                                    if (r_or='1') then
                                        --  it means there's at least another active request besides this
                                        lIdx := lIdx + 1;
                                        r_stage <= s_SCAN_0;
                                    else
                                        --  it means that there are no more requests
                                        r_stage <= s_IDLE;
                                    end if;
                            end case;
                        end if;
                    end if;
                end process MAIN;
    --  assignments
    busy <= r_busy;
    grant_lines <= r_grant_lines;
end Behavioral;
