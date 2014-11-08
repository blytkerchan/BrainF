-- Generic SPI Slave
-- sets the output data bit on the rising edge of the clock, reads the 
-- data input bit on the falling edge. 
-- To use, read the data_O output on the rising edge of 
-- (data_ready_O and new_data_byte_O), set data_I to something you want to send and 
-- wait for a rising edge on data_ack_O before putting another one in. 
-- Data sent by the slave will be aligned to 8-bit boundaries, so if you don't
-- have any data ready to send (data_ready_I is set) when a byte starts to be sent,
-- the slave will pull its output low for the duration of the byte. You have between
-- the rising edge of the SPI clock for the last bit of a byte and the next rising 
-- edge to provide new data.
-- the spi_clock_I, spi_slave_select_NI and spi_mosi_I signals should be debounced
-- before being fed to this component -- you know better how much noise to expect
-- than I do.
-- Version: 20141019
-- Author:  Ronald Landheer-Cieslak
-- Copyright (c) 2014  Vlinder Software
-- License: LGPL-3.0
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SPISlave is
    port(
          clock                 : in std_logic
        ; resetN                : in std_logic
        
        -- bus to the outside
        ; spi_clock_I           : in std_logic
        ; spi_slave_select_NI   : in std_logic
        ; spi_mosi_I            : in std_logic
        ; spi_miso_O            : out std_logic
        
        -- internal bus:
        -- signal to this component that data_I contains something
        ; data_ready_I          : in std_logic
        -- data to send
        ; data_I                : in std_logic_vector(7 downto 0)
        -- acknowledge we've copied the byte, so you can provide another one
        ; data_ack_O            : out std_logic
        -- indicate data_O contains valid data from the master
        ; data_ready_O          : out std_logic
        -- signal that we've changed the byte (can be used to push into a FIFO or set an SR flip-flop or something)
        ; new_data_byte_O       : out std_logic
        -- byte from the master
        ; data_O                : out std_logic_vector(7 downto 0)
        );
end entity;
architecture behavior of SPISlave is
    type BitCounter is range 0 to 7;
    
    -- driven by a SR flip-flop
    signal internal_data_ready_O        : std_logic := '0';
    signal internal_data_ready_NO       : std_logic := '1';
    -- driven by p_decoder
    signal set_internal_data_ready_O    : std_logic := '0';
    signal clear_internal_data_ready_O  : std_logic := '1';
    signal prev_spi_clock_I             : std_logic := 'X';
    signal prev_spi_slave_select_NI     : std_logic := 'X';
    signal internal_spi_miso_O          : std_logic := 'Z';
    signal input_bit_count              : BitCounter := 0;
    signal output_bit_count             : BitCounter := 7;
    signal current_input_byte           : std_logic_vector(7 downto 0) := (others => 'X');
    signal outputting_data              : std_logic := '0';
    signal current_output_byte          : std_logic_vector(7 downto 0) := (others => '0');
    signal current_output_byte_valid    : std_logic := '0';
    signal prev_data_ready_I            : std_logic := 'X';
    signal data_ack_on_first_seen       : std_logic := '0';
    signal data_ack_on_byte_change      : std_logic := '0';
    signal read_select                  : std_logic := '0';
begin
    -- flip-flop for the data-ready output signal
    internal_data_ready_O <= not internal_data_ready_NO or set_internal_data_ready_O;
    internal_data_ready_NO <= not internal_data_ready_O or clear_internal_data_ready_O;
    data_ready_O <= internal_data_ready_O;
    -- let the client code know we produced a new byte
    new_data_byte_O <= set_internal_data_ready_O;
    -- wire-through for the MISO output
    spi_miso_O <= internal_spi_miso_O;
    -- acknowledge consuming a byte
    data_ack_O <= data_ack_on_byte_change or data_ack_on_first_seen;
    
    p_decoder : process(clock, resetN)
    begin
        if resetN = '0' then
            prev_spi_clock_I         <= 'X';
            prev_spi_slave_select_NI <= 'X';
            clear_internal_data_ready_O <= '1';
            data_O <= (others => 'X');
            internal_spi_miso_O <= 'Z';
            set_internal_data_ready_O <= '0';
            current_input_byte <= (others => 'X');
            input_bit_count <= 0;
            output_bit_count <= 7;
            outputting_data <= '0';
            current_output_byte <= (others => '0');
            current_output_byte_valid <= '0';
            prev_data_ready_I <= 'X';
            data_ack_on_first_seen <= '0';
            data_ack_on_byte_change <= '0';
            read_select <= '0';

        else
            if rising_edge(clock) then
                -- detect a falling edge of the spi_slave_select_NI input
                if prev_spi_slave_select_NI = '1' and spi_slave_select_NI = '0' then
                    clear_internal_data_ready_O <= '1';
                    -- counters should already be OK at this point: either because we're coming out of a complete reset or because we have previously been deselected
                -- on a rising edge (when we're deselected) reset the counters so we can't get desynchronized if we get deselected in the middle of a byte
                elsif prev_spi_slave_select_NI = '0' and spi_slave_select_NI = '1' then
                    output_bit_count <= 7;
                    input_bit_count <= 0;
                    read_select <= '0';
                else
                    clear_internal_data_ready_O <= '0';
                end if;
                prev_spi_slave_select_NI <= spi_slave_select_NI;
                -- detect new output data
                if prev_data_ready_I = '0'and data_ready_I = '1' then
                    current_output_byte <= data_I;
                    current_output_byte_valid <= '1';
                    data_ack_on_first_seen <= '1';
                else 
                    data_ack_on_first_seen <= '0';
                end if;
                prev_data_ready_I <= data_ready_I;
                -- detect edges of the input clock
                if spi_slave_select_NI = '0' then -- we are selected
                    if prev_spi_clock_I = '0' and spi_clock_I = '1' then -- rising edge of the clock - write a bit if we have any
                        -- start outputting data if we are at the start of a byte boundary, or if we were already outputting a byte
                        if current_output_byte_valid = '1' and (outputting_data = '1' or output_bit_count = 7) then
                            internal_spi_miso_O <= current_output_byte(7);
                            outputting_data <= '1';
                        else
                            internal_spi_miso_O <= '0';
                            outputting_data <= '0';
                        end if;
                        -- if we just decided to output the last bit of the byte, load the next byte if we have one, or invalidate the current byte if we don't.
                        -- if we do load a new byte, we should acknowledge it.
                        -- if we're not at the last bit, just shift a bit out of the register
                        if (output_bit_count = 0) then
                            -- we should, of course, only take the byte if we've output the current one. Otherwise, we should leave it there until we do.
                            if outputting_data = '1' then
                                current_output_byte <= data_I;
                                current_output_byte_valid <= data_ready_I;
                                data_ack_on_byte_change <= '1';
                            else
                                data_ack_on_byte_change <= '0';
                            end if;
                            output_bit_count <= 7;
                        else
                            -- shift out a bit
                            data_ack_on_byte_change <= '0';
                            output_bit_count <= output_bit_count - 1;
                            current_output_byte <= current_output_byte(6 downto 0) & '0';
                        end if;
                        set_internal_data_ready_O <= '0';
                        read_select <= '1';
                    elsif read_select = '1' and prev_spi_clock_I = '1' and spi_clock_I = '0' then -- falling edge of the clock - read a bit
                        if input_bit_count = 7 then
                            set_internal_data_ready_O <= '1';
                            data_O <= current_input_byte(6 downto 0) & spi_mosi_I;
                            input_bit_count <= 0;
                        else
                            set_internal_data_ready_O <= '0';
                            input_bit_count <= input_bit_count + 1;
                        end if;
                        current_input_byte <= current_input_byte(6 downto 0) & spi_mosi_I;
                    else
                        set_internal_data_ready_O <= '0';
                    end if;
                else
                    internal_spi_miso_O <= 'Z';
                    set_internal_data_ready_O <= '0';
                end if;
                prev_spi_clock_I <= spi_clock_I;
            end if;
        end if;
    end process;
end architecture;
