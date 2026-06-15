import struct
import csv

# Open de binaire input en de CSV output
with open('isotopes.bin', 'rb') as f_bin, open('isotopes_leesbaar.csv', 'w', newline='', encoding='utf-8') as f_csv:
    writer = csv.writer(f_csv)
    
    # Prachtige kolomkoppen gebaseerd op je assembly-structuur
    writer.writerow(['Z (Protonen)', 'N (Neutronen)', 'A (Massagetal)', 'Symbool', 'Halveringstijd (s)', 'k-Waarde', 'Sort_Key'])
    
    binary_data = f_bin.read()
    
    # Lus door het bestand met stappen van exact 64 bytes
    for i in range(0, len(binary_data), 64):
        record = binary_data[i:i+64]
        if len(record) < 64:
            break  # Stop als we aan het einde van het bestand zijn
            
        # Unpack conform de types: 3x uint64 (Q), 8-byte string (8s), 3x double (d)
        # De resterende 8 bytes padding (56-64) negeren we via de data-slice.
        z, n, a, sym_bytes, hl, k_val, sort_key = struct.unpack('<QQQ8sddd', record[:56])
        
        # Sloop de null-terminators (\x00) uit de ASCII-string van het chemisch symbool
        symbol = sym_bytes.decode('ascii', errors='ignore').strip('\x00')
        
        # Schrijf de rij naar de CSV
        writer.writerow([z, n, a, symbol, hl, k_val, sort_key])

print("✅ isotopes_leesbaar.csv succesvol gegenereerd uit de 64-byte database!")
