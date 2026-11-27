import 'package:belltide/src/clickup/clickup_models.dart';
import 'package:belltide/src/clickup/task_search.dart';
import 'package:flutter_test/flutter_test.dart';

ClickUpTask task(String id, String name,
        {String? parent, String list = 'Physio', int updated = 0, String? customId, String status = 'to do'}) =>
    ClickUpTask(
      id: id,
      name: name,
      teamId: '1',
      parentId: parent,
      listName: list,
      dateUpdated: updated,
      customId: customId,
      status: status,
    );

void main() {
  final tasks = [
    task('1', 'Knee rehab', updated: 10),
    task('2', 'Quad sets', parent: '1', updated: 30),
    task('3', 'Weekly report', list: 'Work', updated: 20, customId: 'DEV-42'),
    task('4', 'Rehab notes for knee', updated: 40),
    task('5', 'Stretch hamstrings', updated: 5, status: 'in progress'),
  ];
  List<String> ids(String q) => searchTasks(tasks, q).map((t) => t.id).toList();

  test('empty query lists the most recently updated first', () {
    expect(ids(''), ['4', '2', '3', '1', '5']);
  });

  test('every word must match, in any order', () {
    expect(ids('knee rehab'), ['1', '4', '2']);
    expect(ids('rehab knee'), ['4', '1', '2']);
  });

  test('exact and prefix name matches rank first', () {
    expect(ids('knee rehab').first, '1');
    expect(ids('rehab').first, '4');
  });

  test('subtasks match on their parent task name', () {
    expect(ids('knee'), contains('2'));
    expect(ids('quad'), ['2']);
  });

  test('matches custom ids, lists and statuses, ignoring case', () {
    expect(ids('dev-42'), ['3']);
    expect(ids('WORK'), ['3']);
    expect(ids('in progress'), ['5']);
  });

  test('no match returns nothing', () {
    expect(ids('zebra'), isEmpty);
  });
}
