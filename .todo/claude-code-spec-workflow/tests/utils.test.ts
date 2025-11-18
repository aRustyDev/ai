import { promises as fs } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import { detectProjectType, fileExists, ensureDirectory } from '../src/utils';

describe('Utils', () => {
  let tempDir: string;

  beforeEach(async () => {
    tempDir = await fs.mkdtemp(join(tmpdir(), 'claude-spec-test-'));
  });

  afterEach(async () => {
    await fs.rm(tempDir, { recursive: true, force: true });
  });

  describe('detectProjectType', () => {
    test('should detect Node.js project', async () => {
      await fs.writeFile(join(tempDir, 'package.json'), '{}');
      
      const types = await detectProjectType(tempDir);
      expect(types).toContain('Node.js');
    });

    test('should detect Python project', async () => {
      await fs.writeFile(join(tempDir, 'requirements.txt'), 'flask==2.0.0');
      
      const types = await detectProjectType(tempDir);
      expect(types).toContain('Python');
    });

    test('should detect multiple project types', async () => {
      await fs.writeFile(join(tempDir, 'package.json'), '{}');
      await fs.writeFile(join(tempDir, 'requirements.txt'), 'flask==2.0.0');
      
      const types = await detectProjectType(tempDir);
      expect(types).toContain('Node.js');
      expect(types).toContain('Python');
    });

    test('should return empty array for unknown project', async () => {
      const types = await detectProjectType(tempDir);
      expect(types).toEqual([]);
    });
  });

  describe('fileExists', () => {
    test('should return true for existing file', async () => {
      const testFile = join(tempDir, 'test.txt');
      await fs.writeFile(testFile, 'test content');
      
      expect(await fileExists(testFile)).toBe(true);
    });

    test('should return false for non-existing file', async () => {
      const testFile = join(tempDir, 'non-existent.txt');
      
      expect(await fileExists(testFile)).toBe(false);
    });
  });

  describe('ensureDirectory', () => {
    test('should create directory if it does not exist', async () => {
      const testDir = join(tempDir, 'new-directory');
      
      await ensureDirectory(testDir);
      
      expect(await fileExists(testDir)).toBe(true);
    });

    test('should not fail if directory already exists', async () => {
      const testDir = join(tempDir, 'existing-directory');
      await fs.mkdir(testDir);
      
      await expect(ensureDirectory(testDir)).resolves.not.toThrow();
    });

    test('should create nested directories', async () => {
      const testDir = join(tempDir, 'nested', 'directory', 'structure');
      
      await ensureDirectory(testDir);
      
      expect(await fileExists(testDir)).toBe(true);
    });
  });
});