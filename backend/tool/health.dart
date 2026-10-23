import 'dart:io';
Future<void> main()async{
  final client=HttpClient();try{final request=await client.getUrl(Uri.parse('http://127.0.0.1:${Platform.environment['PORT'] ?? '8080'}/health'));final response=await request.close().timeout(const Duration(seconds:5));await response.drain();if(response.statusCode!=200)exitCode=1;}catch(_){exitCode=1;}finally{client.close(force:true);}
}
