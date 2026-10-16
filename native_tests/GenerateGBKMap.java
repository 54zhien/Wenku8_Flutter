import java.io.DataOutputStream;
import java.nio.ByteBuffer;
import java.nio.CharBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.Charset;
import java.nio.charset.CodingErrorAction;
import java.nio.file.Files;
import java.nio.file.Path;

/** Generate the strict Java GBK mapping used by the original Android bridge. */
class GenerateGBKMap {
  public static void main(String[] args) throws Exception {
    if (args.length != 1) throw new IllegalArgumentException("Provide output file");
    Path output = Path.of(args[0]);
    Files.createDirectories(output.toAbsolutePath().getParent());
    Charset charset = Charset.forName("GBK");
    int count = 0;
    try (var stream = new DataOutputStream(Files.newOutputStream(output))) {
      // ASCII is encoded directly. Non-ASCII mappings are sorted BMP records:
      // unsigned big-endian UInt16 Unicode scalar, UInt16 encoded GBK bytes.
      for (int point = 128; point <= 0xffff; point++) {
        if (Character.isSurrogate((char) point)) continue;
        try {
          ByteBuffer bytes = charset.newEncoder()
              .onMalformedInput(CodingErrorAction.REPORT)
              .onUnmappableCharacter(CodingErrorAction.REPORT)
              .encode(CharBuffer.wrap(new char[] {(char) point}));
          int value = 0;
          if (bytes.remaining() < 1 || bytes.remaining() > 2) throw new IllegalStateException("Non-GBK width");
          while (bytes.hasRemaining()) value = (value << 8) | (bytes.get() & 0xff);
          stream.writeShort(point);
          stream.writeShort(value);
          count++;
        } catch (CharacterCodingException unmappable) {
          // Strict GBK: unmappable scalars are absent, never replaced by '?'.
        }
      }
    }
    System.out.println("Strict Java GBK mapping: " + count + " records, " + Files.size(output) + " bytes");
  }
}
