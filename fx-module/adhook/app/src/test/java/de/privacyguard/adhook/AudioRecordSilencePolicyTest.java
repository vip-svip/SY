package de.privacyguard.adhook;
import org.junit.Test; import java.nio.ByteBuffer; import static org.junit.Assert.*;
public class AudioRecordSilencePolicyTest {
 @Test public void zeroesOnlyReturnedByteRangeAndHonorsOffset(){byte[] a={9,8,7,6,5,4};AudioRecordSilencePolicy.zero(new Object[]{a,2,3},2,0);assertArrayEquals(new byte[]{9,8,0,0,5,4},a);}
 @Test public void zeroesShortAndFloatSamples(){short[] s={1,2,3,4};float[] f={1f,2f,3f};AudioRecordSilencePolicy.zero(new Object[]{s},3,0);AudioRecordSilencePolicy.zero(new Object[]{f},2,0);assertArrayEquals(new short[]{0,0,0,4},s);assertArrayEquals(new float[]{0f,0f,3f},f,0f);}
 @Test public void zeroesByteBufferOnlyInNewlyReadRegion(){ByteBuffer b=ByteBuffer.wrap(new byte[]{1,2,3,4,5});AudioRecordSilencePolicy.zero(new Object[]{b,3},3,1);assertArrayEquals(new byte[]{1,0,0,0,5},b.array());}
 @Test public void zeroesDirectByteBufferAtOriginalPosition(){ByteBuffer b=ByteBuffer.allocateDirect(6);b.put(new byte[]{1,2,3,4,5,6});b.position(2);AudioRecordSilencePolicy.zero(new Object[]{b,4,0},3,2);assertEquals(1,b.get(0));assertEquals(2,b.get(1));assertEquals(0,b.get(2));assertEquals(0,b.get(3));assertEquals(0,b.get(4));assertEquals(6,b.get(5));}
 @Test public void clampsArrayOffsetAndReadCountToBufferBounds(){byte[] a={1,2,3};AudioRecordSilencePolicy.zero(new Object[]{a,2,99},99,0);assertArrayEquals(new byte[]{1,2,0},a);AudioRecordSilencePolicy.zero(new Object[]{a,99,1},1,0);assertArrayEquals(new byte[]{1,2,0},a);}
 @Test public void ignoresInvalidOrEmptyReads(){byte[] a={1,2};AudioRecordSilencePolicy.zero(new Object[]{a},0,0);AudioRecordSilencePolicy.zero(new Object[]{a},-1,0);assertArrayEquals(new byte[]{1,2},a);}
}