library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

--  in this case the hardware interface has to keep in mind how the i2c transactions work
--  the bus should be built as follows:
--  R/W bit
--  7 bit device address
--  8 bits for number of 8 bit words to fully specify the device's register to be acted on
--  8 bits for number of bytes to send in a transaction
--  8 bits for data
--  so the bus is overall a 32 bit bus, allowing to transfer 4 bytes at a time
--  we also need a buffer to store this data here.
entity hwdrv_I2C is
    generic (
        --  bus topology
        data_width: integer := 8;
        ndevs: natural := 8
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  HARDWARE LINES
        i2c_scl: out std_logic;
        i2c_sda: inout std_logic;
        --  INTERFACE WITH HARDWARE BUS
        --  system bus interface signals
        bus_request: in std_logic_vector(ndevs-1 downto 0);
        bus_grant: out std_logic_vector(ndevs-1 downto 0);
        bus_busy: out std_logic;
        --  output databus lanes
        data_out: out std_logic_vector(7 downto 0);
        data_drdy: out std_logic;
        data_ack: in std_logic;
        --  input databus lanes
        data_in: in std_logic_vector(7 downto 0);
        data_latch: in std_logic;
        data_in_keep: in std_logic;
        data_done: out std_logic;
        -- debug
        dbg: out natural;
        dbg_trx: out natural
    );
end hwdrv_I2C;

architecture Behavioral of hwdrv_I2C is
    --  control signals for i2c
    signal i2c_bus_speed: std_logic_vector(1 downto 0) := "00";
    signal r_i2c_cmd: std_logic := '0';
    signal r_i2c_dev_addr: std_logic_vector(6 downto 0) := (others=>'0');
    signal r_i2c_dev_reg_N: std_logic_vector(7 downto 0) := (others=>'0');
    signal r_i2c_N_tr: std_logic_vector(7 downto 0) := (others=>'0');
    signal r_i2c_start_send: std_logic := '0';
    signal r_i2c_data_in: std_logic_vector(7 downto 0) := (others=>'0');
    signal s_i2c_done: std_logic := '0';
    signal s_i2c_data_out: std_logic_vector(7 downto 0);
    signal s_i2c_drdy: std_logic;
    signal s_i2c_error: std_logic;
    
    --  sampling signals for the i2c driver
    signal ss_i2c_done: std_logic;
    signal ss_i2c_drdy: std_logic;
    signal ss_i2c_error: std_logic;
    signal ss_i2c_data_out: std_logic_vector(7 downto 0);
    
    --  driving signals for interface
    signal r_int_data_out: std_logic_vector(7 downto 0) := (others=>'0');
    signal r_int_data_drdy: std_logic := '0';
    signal r_int_data_done: std_logic := '0';
    
    --  sampling signals for interface
    signal ss_int_data_ack: std_logic := '0';
    signal ss_int_data_keep: std_logic := '0';
    signal ss_int_data_latch: std_logic := '0';
    
    signal ss_int_data_in: std_logic_vector(7 downto 0) := (others=>'0');
    
    
    --  state machine
    type t_SM is (s_INIT, s_IDLE, s_INT_0, s_I2C_init, s_I2C_devreg, s_I2C_nt, s_A_0, s_A_1, s_W_0, s_W_1, s_R_0, s_R_1, s_ERR_0, s_ERR_1);
    signal r_stage: t_SM := s_INIT;
    signal r_jump_0: t_SM;
    signal r_jump_1: t_SM;
    signal r_jump_2: t_SM;
        
begin
    --  assignments
    data_out <= r_int_data_out;
    data_drdy <= r_int_data_drdy;
    data_done <= r_int_data_done;

    --  hardware access arbiter
    HWARB:  entity work.bus_arb(Behavioral)
                generic map (
                    n_rq_lines => ndevs
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  request lines
                    rq_lines => bus_request,
                    grant_lines => bus_grant,
                    busy => bus_busy
                );

    --  I2C TRANSCEIVER
    HWI2C:  entity work.i2c_trx(Behavioral)
            port map (
                sysClk => sysClk,
                sysRstb => sysRstb,
                --  i2c bus
                i2c_scl => i2c_scl,
                i2c_sda => i2c_sda,
                --  i2c transceiver control
                bus_speed => i2c_bus_speed,
                bus_cmd => r_i2c_cmd,
                dev_addr => r_i2c_dev_addr,
                dev_reg_N => r_i2c_dev_reg_N,
                dev_N_tr => r_i2c_N_tr,
                start_send => r_i2c_start_send,
                data_input => r_i2c_data_in,
                done_send => s_i2c_done,
                data_output => s_i2c_data_out,
                drdy => s_i2c_drdy,
                dev_error => s_i2c_error,
                --  debug
                dbg => dbg_trx
            );
    
    --  Sampling and Main process
    SAMPLER:    process(sysClk)
                begin
                    if (rising_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                --  sampling signals for the i2c driver
                                ss_i2c_done <= '0';
                                ss_i2c_drdy <= '0';
                                ss_i2c_error <= '0';
                                --  samplign signals for the interface
                                ss_int_data_ack <= '0';
                                ss_int_data_keep <= '0';
                                ss_int_data_latch <= '0';
                        
                            when s_IDLE =>
                                ss_int_data_latch <= data_latch;
                                ss_int_data_in <= data_in;
                                ss_int_data_keep <= data_in_keep;
                            
                            when s_INT_0 =>
                                ss_int_data_latch <= data_latch;
                            
                            when s_A_0 =>
                                ss_i2c_drdy <= s_i2c_drdy; 
                                ss_i2c_error <= s_i2c_error;
                                
                            when s_A_1 =>
                                ss_i2c_drdy <= s_i2c_drdy;
                            
                            when s_R_0 =>
                                ss_i2c_drdy <= s_i2c_drdy;
                                ss_i2c_done <= s_i2c_done;
                                ss_i2c_data_out <= s_i2c_data_out;
                            
                            when s_R_1 =>
                                ss_i2c_drdy <= s_i2c_drdy;
                            
                            when s_W_0 =>
                                ss_i2c_drdy <= s_i2c_drdy;
                                ss_i2c_done <= s_i2c_done;
                                ss_i2c_data_out <= s_i2c_data_out;
                            
                            when s_W_1 =>
                                ss_i2c_drdy <= s_i2c_drdy;
                            
                            when s_ERR_0 =>
                                ss_i2c_error <= s_i2c_error;
                            
                            when others =>
                                null;
                        end case;
                    end if;
                end process SAMPLER;

    MAIN:       process(sysClk)
                    variable cond: std_logic_vector(1 downto 0) := "00";
                    variable hasReg: std_logic := '0';
                    variable nbytes_addr: natural := 0;
                    variable nbytes_data: natural := 0;
                    variable bc: natural := 0;
                    variable delay: natural := 0;
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            --  reset
                            r_stage <= s_INIT;
                        else
                            --  state machine
                            case (r_stage) is
                                when s_INIT =>
                                    --  hardware bus outputs
                                    r_int_data_out <= (others=>'0');
                                    r_int_data_drdy <= '0';
                                    r_int_data_done <= '0';
                                    --  i2c driver controls
                                    r_i2c_cmd <= '0';
                                    r_i2c_dev_addr <= (others=>'0');
                                    r_i2c_dev_reg_N <= (others=>'0');
                                    r_i2c_N_tr <= (others=>'0');
                                    r_i2c_start_send <= '0';
                                    r_i2c_data_in <= (others=>'0');
                                    r_jump_0 <= s_I2C_init;
                                    bc := 0;
                                    nbytes_addr := 0;
                                    nbytes_data := 0;
                                    hasReg := '0';
                                    --  ready
                                    r_stage <= s_IDLE;
                                
                                when s_IDLE =>
                                    dbg <= 0;
                                    --  waiting for an event on the hardware bus
                                    if (ss_int_data_latch='1') then
                                        --  the hardware bus is sending something
                                        r_stage <= r_jump_0;
                                    else
                                        --  waiting for something to happen
                                        r_stage <= s_IDLE;
                                    end if;
                                
                                when s_INT_0 =>
                                    dbg <= 1;
                                    if (ss_int_data_latch='0') then
                                        r_int_data_drdy <= '0';
                                        r_int_data_done <= '0';
                                        r_int_data_out <= (others=>'0');
                                        r_stage <= s_IDLE;
                                    else
                                        r_int_data_drdy <= '1';
                                        r_stage <= s_INT_0;
                                    end if;
                                
                                when s_I2C_init =>
                                    dbg <= 2;
                                    --  the initialization data is arriving, so
                                    r_i2c_cmd <= ss_int_data_in(7);
                                    r_i2c_dev_addr <= ss_int_data_in(6 downto 0);
                                    r_jump_0 <= s_I2C_devreg;
                                    r_stage <= s_INT_0;
                                
                                when s_I2C_devreg =>
                                    dbg <= 3;
                                    --  the number of bytes to specify the register's internal address
                                    r_i2c_dev_reg_N <= ss_int_data_in;
                                    nbytes_addr := to_integer(unsigned(ss_int_data_in));
                                    r_jump_0 <= s_I2C_nt;
                                    r_stage <= s_INT_0;
                                
                                when s_I2C_nt =>
                                    dbg <= 4;
                                    r_i2c_N_tr <= ss_int_data_in;
                                    nbytes_data := to_integer(unsigned(ss_int_data_in));
                                    r_jump_0 <= s_A_0;
                                    if (nbytes_addr=0) then
                                        if (r_i2c_cmd='0') then
                                            r_jump_1 <= s_W_0;
                                        else
                                            r_jump_1 <= s_R_0;
                                        end if;
                                    else
                                        r_jump_1 <= s_A_1;
                                    end if;
                                    bc := 0;
                                    r_stage <= s_INT_0;
                                
                                -------------------------------------------------------------------------------
                                --
                                --  ADDRESS PLACING
                                --
                                -------------------------------------------------------------------------------
                                when s_A_0 =>
                                    dbg <= 5;
                                    cond := (ss_i2c_drdy & ss_i2c_error);
                                    case (cond) is
                                        when "00" =>
                                            --  starting i2c transaction
                                            r_i2c_data_in <= ss_int_data_in;
                                            r_i2c_start_send <= '1';
                                            r_stage <= s_A_0;
                                        
                                        when "01" =>
                                            --  an error occurred
                                            r_stage <= s_ERR_0;
                                        
                                        when "10" =>
                                            --  success
                                            bc := bc + 1;
                                            r_stage <= r_jump_1;
                                      
                                        when "11" =>
                                            --  impossible condition
                                            r_stage <= s_ERR_0;
                                    end case;
                                
                                when s_A_1 =>
                                    dbg <= 6;
                                    if (ss_i2c_drdy='0') then
                                        if (bc=nbytes_addr) then
                                            bc := 0;
                                            if (r_i2c_cmd='0') then
                                                r_jump_0 <= s_W_0;
                                            else
                                                r_jump_0 <= s_R_0;
                                            end if;
                                        else
                                            r_jump_0 <= s_A_0;
                                        end if;
                                        r_stage <= s_INT_0;
                                    else
                                        --  waiting
                                        r_i2c_start_send <= '0';
                                        r_stage <= s_A_1;
                                    end if;

                                -------------------------------------------------------------------------------
                                --
                                --  READ command
                                --
                                -------------------------------------------------------------------------------
                                when s_R_0 =>
                                    dbg <= 7;
                                    if (ss_i2c_drdy='1') then
                                        --  data has appeared
                                        r_int_data_out <= ss_i2c_data_out;
                                        r_stage <= s_R_1;
                                    else
                                        --  waiting for data to appear
                                        r_i2c_data_in <= (others=>'0');
                                        r_i2c_start_send <= '1';
                                        r_stage <= s_R_0;
                                    end if;
                                
                                when s_R_1 =>
                                    dbg <= 8;
                                    if (ss_i2c_drdy='0') then
                                        if (ss_i2c_done='1') then
                                            --  end of read operations
                                            r_int_data_done <= '1';
                                            r_jump_0 <= s_I2C_init;
                                        else
                                            --  still need to read more
                                            r_int_data_done <= '0';
                                            r_jump_0 <= s_R_0;
                                        end if;
                                        --r_int_data_drdy <= '1';
                                        r_stage <= s_INT_0;
                                    else
                                        r_i2c_start_send <= '0';
                                        r_stage <= s_R_1;
                                    end if;
                                
                                -------------------------------------------------------------------------------
                                --
                                --  WRITE command
                                --
                                -------------------------------------------------------------------------------
                                when s_W_0 =>
                                    dbg <= 9;
                                    if (ss_i2c_drdy='1') then
                                        --  data has been written
                                        r_int_data_out <= ss_i2c_data_out;
                                        r_stage <= s_W_1;
                                    else
                                        --  waiting
                                        r_i2c_data_in <= ss_int_data_in;
                                        r_i2c_start_send <= '1';
                                        r_stage <= s_W_0;
                                    end if;
                                
                                when s_W_1 =>
                                    dbg <= 10;
                                    if (ss_i2c_drdy='0') then
                                        if (ss_i2c_done='1') then
                                            --  done with writing
                                            r_int_data_done <= '1';
                                            r_jump_0 <= s_I2C_init;
                                        else
                                            --  have to write more
                                            r_int_data_done <= '0';
                                            r_jump_0 <= s_W_0;
                                        end if;
                                        --r_int_data_drdy <= '1';
                                        r_stage <= s_INT_0;
                                    else
                                        r_i2c_start_send <= '0';
                                        r_stage <= s_W_1;
                                    end if;
                                
                                -------------------------------------------------------------------------------
                                --  ERROR CONDITION
                                -------------------------------------------------------------------------------
                                when s_ERR_0 =>
                                    --  in this case the device might be busy or not connected to the bus
                                    --  we wait for 50 microseconds and do a poll to see if it is ready
                                    if (ss_i2c_error='0') then
                                        delay := 0;
                                        r_stage <= s_ERR_1;
                                    else
                                        --  resetting the error
                                        r_i2c_start_send <= '0';
                                        r_stage <= s_ERR_0;
                                    end if;
                                
                                when s_ERR_1 =>
                                    if (delay=4999) then
                                        --  trying again
                                        delay := 0;
                                        r_stage <= s_A_0;
                                    else
                                        delay := delay + 1;
                                        r_stage <= s_ERR_1;
                                    end if;
                                    
                                
                                when others =>
                                    r_stage <= s_IDLE;
                            end case;
                        end if;
                    end if;
                end process MAIN;

end Behavioral;

