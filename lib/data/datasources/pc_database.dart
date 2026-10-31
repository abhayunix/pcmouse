import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/paired_pc_model.dart';

class PcDatabase {
  static final PcDatabase instance = PcDatabase._init();
  static Database? _database;

  PcDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('paired_pcs.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE paired_pcs (
        id TEXT PRIMARY KEY,
        pcName TEXT NOT NULL,
        ipAddress TEXT NOT NULL,
        port INTEGER NOT NULL,
        sessionToken TEXT NOT NULL,
        isLastConnected INTEGER NOT NULL,
        lastSeen INTEGER NOT NULL
      )
    ''');
  }

  Future<void> savePc(PairedPcModel pc) async {
    final db = await instance.database;
    await db.insert(
      'paired_pcs',
      pc.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<PairedPcModel>> getAllPcs() async {
    final db = await instance.database;
    final result = await db.query('paired_pcs', orderBy: 'lastSeen DESC');
    return result.map((json) => PairedPcModel.fromMap(json)).toList();
  }

  Future<void> deletePc(String id) async {
    final db = await instance.database;
    await db.delete('paired_pcs', where: 'id = ?', whereArgs: [id]);
  }
}
