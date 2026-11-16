import io
import unittest
import zipfile

from generate_android_notices import coordinates, embedded_notices


class NoticeGenerationTest(unittest.TestCase):
    def test_selected_versions_override_requests_and_ignore_constraints(self):
        graph = '''+--- com.google.guava:guava:31.0.1-jre -> 33.7.2-android
|    \\--- com.squareup.okio:okio:{require 1.17.6} -> 1.17.6
\\--- com.google.guava:guava:33.7.2-android (c)
'''
        self.assertEqual(coordinates(graph), {
            ('com.google.guava', 'guava', '33.7.2-android'),
            ('com.squareup.okio', 'okio', '1.17.6'),
        })

    def test_aar_retains_licences_inside_classes_jar(self):
        nested = io.BytesIO()
        with zipfile.ZipFile(nested, 'w') as archive:
            archive.writestr('META-INF/NOTICE.txt', 'Original copyright and notice')
        aar = io.BytesIO()
        with zipfile.ZipFile(aar, 'w') as archive:
            archive.writestr('classes.jar', nested.getvalue())
            archive.writestr('META-INF/LICENSE', 'Full licence')
        self.assertEqual(embedded_notices(aar.getvalue()), [
            ('META-INF/LICENSE', 'Full licence'),
            ('classes.jar/META-INF/NOTICE.txt', 'Original copyright and notice'),
        ])


if __name__ == '__main__':
    unittest.main()
