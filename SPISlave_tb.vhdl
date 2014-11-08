-- Version: 20141019
-- Author:  Ronald Landheer-Cieslak
-- Copyright (c) 2014  Vlinder Software
-- License: LGPL-3.0
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SPISlave_tb is
end entity;
architecture behavior of SPISlave_tb is 
    type TestState is (
          idle
        , select_slave
        , wait_for_the_first_clock_tick
        , wait_for_eight_spi_clock_ticks
        , check_slave_output_from_one_byte_of_zeroes
        , check_slave_output_from_one_byte_of_zeroes_2
        , prepare_master_data
        , send_master_data
        , check_final_byte
        );
    constant IDLE_DURATION : integer := 5000;
    constant CHECK_SLAVE_OUTPUT_FROM_ONE_BYTE_OF_ZEROES_2_DURATION : integer := 1700;

    component SPISlave is
        port(
              clock                 : in std_logic
            ; resetN                : in std_logic
            ; spi_clock_I           : in std_logic
            ; spi_slave_select_NI   : in std_logic
            ; spi_mosi_I            : in std_logic
            ; spi_miso_O            : out std_logic
            ; data_ready_I          : in std_logic
            ; data_I                : in std_logic_vector(7 downto 0)
            ; data_ack_O            : out std_logic
            ; data_ready_O          : out std_logic
            ; new_data_byte_O       : out std_logic
            ; data_O                : out std_logic_vector(7 downto 0)
            );
    end component;
    
    signal clock                        : std_logic := '0';
    signal resetN                       : std_logic := '1';
    
    signal internal_spi_clock           : std_logic := '0';
    signal spi_clock                    : std_logic := '0';
    signal enable_spi_clock             : std_logic := '0';
    
    signal test_state                   : TestState := idle;
    
    signal spi_miso                     : std_logic;
    signal data_ready_from_the_slave    : std_logic := '0';
    signal data_ready_to_the_slave      : std_logic := '0';
    signal data_to_the_slave            : std_logic_vector(7 downto 0) := (others => '0');
    signal data_ack_from_the_slave      : std_logic := '0';
    signal new_data_byte_from_the_slave : std_logic := '0';
    signal data_from_the_slave          : std_logic_vector(7 downto 0) := (others => '0');
    signal spi_slave_select_NI          : std_logic := '1';
    signal prev_spi_clock               : std_logic := '0';
    signal master_data                  : std_logic_vector(63 downto 0);
    signal spi_mosi                     : std_logic := '0';
begin
    -- we don't really care about the speed of the clock, just as long as it clocks...
    clock <= not clock after 1 ps;
    
    under_test : SPISlave
        port map(
              clock                 => clock
            , resetN                => resetN
            , spi_clock_I           => spi_clock
            , spi_slave_select_NI   => spi_slave_select_NI
            , spi_mosi_I            => spi_mosi
            , spi_miso_O            => spi_miso
            , data_ready_I          => data_ready_to_the_slave
            , data_I                => data_to_the_slave
            , data_ack_O            => data_ack_from_the_slave
            , data_ready_O          => data_ready_from_the_slave
            , new_data_byte_O       => new_data_byte_from_the_slave
            , data_O                => data_from_the_slave
            );
    p_generate_spi_clock : process(clock)
        variable counter : integer := 0;
    begin
        if rising_edge(clock) then
            if counter = 50 then
                counter := 0;
                internal_spi_clock <= not internal_spi_clock;
            else
                counter := counter + 1;
            end if;
        end if;
    end process;
    spi_clock <= enable_spi_clock and internal_spi_clock;
    
    p_test_driver : process(clock)
        variable counter : integer := 0;
    begin
        if rising_edge(clock) then
            case test_state is
            when idle =>
                enable_spi_clock <= '1';
                assert spi_miso = 'Z' report "Slave shouldn't drive unless selected" severity failure;
                assert data_ack_from_the_slave = '0' report "Slave cannot acknowledge data we did not give it" severity failure;
                assert data_ready_from_the_slave = '0' and new_data_byte_from_the_slave = '0' report "Slave cannot produce data when not selected" severity failure;
                if counter = IDLE_DURATION then
                    test_state <= select_slave;
                    counter := 0;
                else
                    counter := counter + 1;
                end if;
            when select_slave =>
                assert spi_miso = 'Z' report "Slave shouldn't drive unless selected" severity failure;
                assert data_ack_from_the_slave = '0' report "Slave cannot acknowledge data we did not give it" severity failure;
                assert data_ready_from_the_slave = '0' and new_data_byte_from_the_slave = '0' report "Slave cannot produce data when not selected" severity failure;
                spi_slave_select_NI <= '0';
                test_state <= wait_for_the_first_clock_tick;
            when wait_for_the_first_clock_tick =>
                assert spi_miso = 'Z' report "Slave only start driving on the first clock tick rising edge" severity failure;
                assert data_ack_from_the_slave = '0' report "Slave cannot acknowledge data we did not give it" severity failure;
                assert data_ready_from_the_slave = '0' and new_data_byte_from_the_slave = '0' report "Slave cannot produce data before selection takes effect and at least one byte was received" severity failure;
                if prev_spi_clock = '0' and spi_clock = '1' then
                    counter := 0;
                    test_state <= wait_for_eight_spi_clock_ticks;
                end if;
            when wait_for_eight_spi_clock_ticks =>
                assert spi_miso = '0' report "Slave should drive low when selected and no data to send" severity failure;
                assert data_ack_from_the_slave = '0' report "Slave cannot acknowledge data we did not give it" severity failure;
                assert data_ready_from_the_slave = '0' and new_data_byte_from_the_slave = '0' report "Slave cannot produce data yet" severity failure;
                test_state <= wait_for_eight_spi_clock_ticks;
                if prev_spi_clock = '1' and spi_clock = '0' then
                    if counter = 7 then
                        counter := 0;
                        spi_slave_select_NI <= '1';
                        test_state <= check_slave_output_from_one_byte_of_zeroes;
                    else
                        counter := counter + 1;
                        spi_slave_select_NI <= '0';
                    end if;
                else
                    spi_slave_select_NI <= '0';
                end if;
            when check_slave_output_from_one_byte_of_zeroes =>
                assert data_ack_from_the_slave = '0' report "Slave cannot acknowledge data we did not give it" severity failure;
                assert data_ready_from_the_slave = '1' and new_data_byte_from_the_slave = '1' report "Slave should now produce a byte" severity failure;
                assert data_from_the_slave = "00000000" report "Byte should be all zeroes" severity failure;
                test_state <= check_slave_output_from_one_byte_of_zeroes_2;
                counter := 0;
            when check_slave_output_from_one_byte_of_zeroes_2 =>
                assert spi_miso = 'Z' report "Slave shouldn't drive unless selected" severity failure;
                assert data_ack_from_the_slave = '0' report "Slave cannot acknowledge data we did not give it" severity failure;
                assert data_ready_from_the_slave = '1' and new_data_byte_from_the_slave = '0' report "Slave should have produced a byte but that byte is no longer new" severity failure;
                assert data_from_the_slave = "00000000" report "Byte should be all zeroes" severity failure;
                if counter = CHECK_SLAVE_OUTPUT_FROM_ONE_BYTE_OF_ZEROES_2_DURATION then
                    test_state <= prepare_master_data;
                else
                    counter := counter + 1;
                end if;
            when prepare_master_data =>
                master_data <= x"c6847e6300257495";
                counter := 63;
                spi_slave_select_NI <= '0';
                test_state <= send_master_data;
            when send_master_data =>
                if new_data_byte_from_the_slave = '1' then
                    if counter >= 55 then
                        assert data_from_the_slave = x"c6" report "Expected C6" severity failure;
                    elsif counter >= 47 then
                        assert data_from_the_slave = x"84" report "Expected C6" severity failure;
                    elsif counter >= 39 then
                        assert data_from_the_slave = x"7e" report "Expected C6" severity failure;
                    elsif counter >= 31 then
                        assert data_from_the_slave = x"63" report "Expected C6" severity failure;
                    elsif counter >= 23 then
                        assert data_from_the_slave = x"00" report "Expected C6" severity failure;
                    elsif counter >= 15 then
                        assert data_from_the_slave = x"25" report "Expected C6" severity failure;
                    elsif counter >= 7 then
                        assert data_from_the_slave = x"74" report "Expected C6" severity failure;
                    end if;
                end if;
                if prev_spi_clock = '0' and spi_clock = '1' then
                    spi_mosi <= master_data(63);
                    master_data <= master_data(62 downto 0) & '0';
                    if counter = 0 then
                        test_state <= check_final_byte;
                    else
                        counter := counter - 1;
                    end if;
                end if;
            when check_final_byte =>
                if new_data_byte_from_the_slave = '1' then
                    assert data_from_the_slave = x"95" report "Expected C6" severity failure;
                end if;
                if prev_spi_clock = '0' and spi_clock = '1' then
                    spi_slave_select_NI <= '1';
                end if;
            when others =>
                null;
            end case;
            prev_spi_clock <= spi_clock;
        end if;
    end process;
end architecture;
